# frozen_string_literal: true

require 'concurrent-ruby'
require 'digest'
require 'rest-client'
require 'zlib'

require_relative 'api'
require_relative 'shutdown_barrier'
require_relative 'trace_tree'

module ApolloTracing
  class Tracer
    attr_reader :compress, :api_key, :schema_tag, :schema_hash, :trace_prepare, :query_signature,
                :service_name, :service_version, :reporting_interval, :max_uncompressed_report_size, :debug_reports
    alias_method :debug_reports?, :debug_reports

    def initialize(compress: true, api_key: nil, schema_tag: nil, schema_hash: nil,
                   service_version: nil, trace_prepare: nil, query_signature: nil,
                   reporting_interval: nil, max_uncompressed_report_size: nil, debug_reports: nil)
      @compress = compress
      @api_key = api_key || ENV.fetch('ENGINE_API_KEY')
      @schema_tag = schema_tag || ENV.fetch('ENGINE_SCHEMA_TAG', 'current')
      @schema_hash = schema_hash
      @service_name = api_key.split(':')[1] unless api_key.nil?
      @service_version = service_version
      @reporting_interval = reporting_interval || 5
      @max_uncompressed_report_size = max_uncompressed_report_size || 4 * 1024 * 1024
      @debug_reports = debug_reports.nil? ? false : debug_reports
      @trace_prepare = trace_prepare || Proc.new {}
      @query_signature = query_signature || Proc.new do |query|
        # TODO: This should be smarter
        query.query_string
      end

      @report_header = ApolloTracing::API::ReportHeader.new(
        hostname: hostname,
        uname: uname,
        agent_version: agent_version,
        service: service_name,
        service_version: service_version,
        schema_tag: schema_tag,
        schema_hash: schema_hash,
        runtime_version: RUBY_DESCRIPTION
      )

      @shutdown_barrier = ApolloTracing::ShutdownBarrier.new
      @trace_queue = Queue.new
    end

    def start_uploader
      @uploader_thread = Thread.new do
        run_uploader
      end
    end

    def synchronize_uploads
      until @trace_queue.empty?
        # If the uploader thread isn't running then the queue will never drain
        break unless @uploader_thread && @uploader_thread.alive?

        sleep(0.1)
      end
    end

    def shutdown_uploader
      return unless @uploader_thread

      @shutdown_barrier.shutdown
      @uploader_thread.join
    end

    def trace(key, data)
      # TODO: Handle lazy field resolution

      if key == 'execute_query'
        query = data.fetch(:query)
        trace = ApolloTracing::API::Trace.new(start_time: to_proto_timestamp(Time.now.utc))
        start_time_nanos = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)
        trace_tree = ApolloTracing::TraceTree.new

        query.context[:apollo_tracing] = {
          trace_start_time_nanos: start_time_nanos,
          tree: trace_tree
        }

        result = yield

        end_time_nanos = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)
        trace.duration_ns = end_time_nanos - start_time_nanos
        trace.end_time = to_proto_timestamp(Time.now.utc)
        trace.root = trace_tree.root

        # TODO: Fill out Trace::Details? Requires removing sensitive data

        # Give consumers a chance to fill out additional details in the trace
        # like Trace::HTTP and client*
        trace_prepare.call(trace, query)

        # TODO: Start dropping traces if the queue is too large
        @trace_queue << ["# #{query.operation_name || '-'}\n#{query_signature.call(query)}", trace]
      elsif key == 'execute_field'
        # TODO: See https://graphql-ruby.org/api-doc/1.9.3/GraphQL/Tracing. Different args are passed when
        # using the interpreter runtime
        start_time_nanos = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)
        result = yield
        end_time_nanos = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)

        # TODO: Handle errors
        context = data.fetch(:context)
        context.fetch(:apollo_tracing).fetch(:tree).add(
          path: context.path,
          parent_type: context.parent_type,
          field: context.field,
          start_time_offset: start_time_nanos - context.dig(:apollo_tracing, :trace_start_time_nanos),
          end_time_offset: end_time_nanos - context.dig(:apollo_tracing, :trace_start_time_nanos)
        )
      else
        result = yield
      end

      result
    end

    private

    def hostname
      @hostname ||= Socket.gethostname
    end

    def agent_version
      @agent_version ||= "apollo-tracing-tracing #{ApolloTracing::VERSION}"
    end

    def uname
      @uname ||= `uname -a`
    end

    def to_proto_timestamp(time)
      Google::Protobuf::Timestamp.new(seconds: time.to_i, nanos: time.nsec)
    end

    def run_uploader
      ApolloTracing.logger.info('Apollo trace uploader starting')
      drain_upload_queue until @shutdown_barrier.await_shutdown(reporting_interval)
      puts 'Stopping uploader run loop'
      drain_upload_queue
    ensure
      ApolloTracing.logger.info('Apollo trace uploader exiting')
    end

    def drain_upload_queue
      trace_report = nil
      report_size = nil
      until @trace_queue.empty?
        if trace_report.nil?
          trace_report = ApolloTracing::API::FullTracesReport.new(header: @report_header)
          report_size = 0
        end

        report_key, trace = @trace_queue.pop(false)
        trace_report.traces_per_query[report_key] ||= ApolloTracing::API::Traces.new
        trace_report.traces_per_query[report_key].trace << trace
        # TODO: Add the encoded Trace to the FullTracesReport to avoid encoding twice
        report_size += trace.class.encode(trace).bytesize + report_key.bytesize

        if report_size >= max_uncompressed_report_size
          send_report(trace_report)
          trace_report = nil
        end
      end

      send_report(trace_report) if trace_report
    end

    def send_report(report)
      if debug_reports?
        ApolloTracing.logger.info("Sending trace report:\n#{JSON.pretty_generate(JSON.parse(report.to_json))}")
      end

      body = compress ? gzip(report.class.encode(report)) : report.class.encode(report)
      headers = {
        'X-Api-Key' => api_key,
        accept_encoding: 'gzip',
        content_encoding: 'gzip'
      }
      RestClient.post(ApolloTracing::API::URL, body, headers)
    rescue RestClient::Exception => e
      ApolloTracing.logger.warning("Failed to send trace report: #{e.class}: #{e.message} - #{e.http_body}")
      # TODO: Add retries with an exponential backoff
    end

    def gzip(data)
      output = StringIO.new
      output.set_encoding('BINARY')
      gz = Zlib::GzipWriter.new(output)
      gz.write(data)
      gz.close
      output.string
    end
  end
end
