# frozen_string_literal: true

require_relative 'api'
require_relative 'trace_channel'
require_relative 'trace_tree'

module ApolloTracing
  class Tracer
    attr_reader :trace_prepare, :query_signature

    def initialize(compress: nil, api_key: nil, schema_tag: nil, schema_hash: nil,
                   service_version: nil, trace_prepare: nil, query_signature: nil,
                   reporting_interval: nil, max_uncompressed_report_size: nil, debug_reports: nil)
      @trace_prepare = trace_prepare || Proc.new {}
      @query_signature = query_signature || Proc.new do |query|
        # TODO: This should be smarter
        query.query_string
      end

      report_header = ApolloTracing::API::ReportHeader.new(
        hostname: hostname,
        uname: uname,
        agent_version: agent_version,
        service: api_key ? api_key.split(':')[1] : '',
        service_version: service_version,
        schema_tag: schema_tag || ENV.fetch('ENGINE_SCHEMA_TAG', 'current'),
        schema_hash: schema_hash,
        runtime_version: RUBY_DESCRIPTION
      )
      @trace_channel = ApolloTracing::TraceChannel.new(
        compress: compress,
        api_key: api_key,
        reporting_interval: reporting_interval,
        max_uncompressed_report_size: max_uncompressed_report_size,
        debug_reports: debug_reports,
        report_header: report_header
      )
    end

    def start_trace_channel
      @trace_channel.start
    end

    def shutdown_trace_channel
      @trace_channel.shutdown
    end

    def flush_trace_channel
      @trace_channel.flush
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

        @trace_channel.queue("# #{query.operation_name || '-'}\n#{query_signature.call(query)}", trace)
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
  end
end
