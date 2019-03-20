# frozen_string_literal: true

require 'digest'
require 'rest-client'
require 'zlib'

require_relative 'api'
require_relative 'trace_tree'

module ApolloTracing
  class Tracer
    attr_reader :compress, :api_key, :schema_tag, :schema_hash, :trace_prepare, :query_signature,
                :service_name, :service_version

    def initialize(compress: true, api_key: nil, schema_tag: nil, schema_hash: nil,
                   service_version: nil, trace_prepare: nil, query_signature: nil)
      @compress = compress
      @api_key = api_key || ENV['ENGINE_API_KEY']
      @schema_tag = schema_tag || ENV.fetch('ENGINE_SCHEMA_TAG', 'current')
      @schema_hash = schema_hash
      @service_name = api_key.split(':')[1] unless api_key.nil?
      @service_version = service_version
      @trace_prepare = trace_prepare || Proc.new {}
      @query_signature = query_signature || Proc.new do |query|
        # TODO: This should be smarter
        query.query_string
      end
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

        # TODO: Batch queries
        trace_report = ApolloTracing::API::FullTracesReport.new(
          header: ApolloTracing::API::ReportHeader.new(
            hostname: hostname,
            uname: uname,
            agent_version: agent_version,
            service: service_name,
            service_version: service_version,
            schema_tag: schema_tag,
            schema_hash: schema_hash,
            runtime_version: RUBY_DESCRIPTION
          )
        )
        trace_report.traces_per_query["# #{query.operation_name || 'unnamed'}\n#{query_signature.call(query)}"] =
          ApolloTracing::API::Traces.new(trace: [trace])

        puts "Generated Report:\n#{JSON.pretty_generate(JSON.parse(trace_report.to_json))}"

        # TODO: Background this (or use async i/o), handle retries, etc.
        send_report(trace_report)
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

    def send_report(report)
      if api_key.nil?
        puts 'Apollo API key not set'
        return
      end

      body = compress ? gzip(report.class.encode(report)) : report.class.encode(report)
      headers = {
        'X-Api-Key' => api_key,
        accept_encoding: 'gzip',
        content_encoding: 'gzip'
      }
      response = RestClient.post(ApolloTracing::API::URL, body, headers)
      puts response.inspect
    rescue RestClient::Exception => e
      puts "Apollo Response: #{e.class}: #{e.message}"
      puts "Body: #{e.http_body}"
      raise
    end

    def gzip(data)
      output = StringIO.new
      output.set_encoding('BINARY')
      gz = Zlib::GzipWriter.new(output)
      gz.write(data)
      gz.close
      output.string
    end

    def to_proto_timestamp(time)
      Google::Protobuf::Timestamp.new(seconds: time.to_i, nanos: time.nsec)
    end
  end
end
