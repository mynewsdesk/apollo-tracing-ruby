# frozen_string_literal: true

require 'rest-client'
require 'zlib'

require_relative 'shutdown_barrier'

module ApolloTracing
  class TraceChannel
    attr_reader :compress, :api_key, :reporting_interval, :max_uncompressed_report_size, :debug_reports
    alias_method :debug_reports?, :debug_reports

    def initialize(report_header:, compress: nil, api_key: nil, reporting_interval: nil,
                   max_uncompressed_report_size: nil, debug_reports: nil)
      @report_header = report_header
      @compress = compress.nil? ? true : compress
      @api_key = api_key || ENV.fetch('ENGINE_API_KEY')
      @reporting_interval = reporting_interval || 5
      @max_uncompressed_report_size = max_uncompressed_report_size || 4 * 1024 * 1024
      @debug_reports = debug_reports.nil? ? false : debug_reports
      @queue = Queue.new
      @shutdown_barrier = ApolloTracing::ShutdownBarrier.new
    end

    def queue(query_key, trace)
      # TODO: Start dropping traces if the queue is too large
      @queue << [query_key, trace]
    end

    def start
      @uploader_thread = Thread.new do
        run_uploader
      end
    end

    def flush
      until @queue.empty?
        # If the uploader thread isn't running then the queue will never drain
        break unless @uploader_thread && @uploader_thread.alive?

        sleep(0.1)
      end
    end

    def shutdown
      return unless @uploader_thread

      @shutdown_barrier.shutdown
      @uploader_thread.join
    end

    private

    def run_uploader
      ApolloTracing.logger.info('Apollo trace uploader starting')
      drain_queue until @shutdown_barrier.await_shutdown(reporting_interval)
      puts 'Stopping uploader run loop'
      drain_queue
    ensure
      ApolloTracing.logger.info('Apollo trace uploader exiting')
    end

    def drain_queue
      trace_report = nil
      report_size = nil
      until @queue.empty?
        if trace_report.nil?
          trace_report = ApolloTracing::API::FullTracesReport.new(header: @report_header)
          report_size = 0
        end

        report_key, trace = @queue.pop(false)
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
