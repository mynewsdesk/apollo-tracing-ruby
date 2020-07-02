# frozen_string_literal: true

require_relative 'proto'
require_relative 'trace_channel'
require_relative 'trace_tree'

module ApolloTracing
  class Tracer
    EXECUTE_QUERY_KEY = 'execute_query'
    SYNC_LAZY_QUERY_RESULT_KEY = 'execute_query_lazy'
    EXECUTE_FIELD_KEY = 'execute_field'
    SYNC_LAZY_FIELD_RESULT_KEY = 'execute_field_lazy'

    attr_reader :trace_prepare, :query_signature

    def initialize(schema_tag: nil, schema_hash: nil, service_version: nil, trace_prepare: nil, query_signature: nil,
                   api_key: nil, **trace_channel_options)
      @trace_prepare = trace_prepare || Proc.new {}
      @query_signature = query_signature || Proc.new do |query|
        # TODO: This should be smarter
        query.query_string
      end

      report_header = ApolloTracing::Proto::ReportHeader.new(
        hostname: hostname,
        uname: uname,
        agent_version: agent_version,
        service: api_key ? api_key.split(':')[1] : '',
        service_version: service_version,
        schema_tag: schema_tag || ENV.fetch('ENGINE_SCHEMA_TAG', 'current'),
        schema_hash: schema_hash,
        runtime_version: RUBY_DESCRIPTION
      )
      @trace_channel = ApolloTracing::TraceChannel.new(report_header: report_header, api_key: api_key,
                                                       **trace_channel_options)
    end

    def trace(key, data)
      case key
      when EXECUTE_QUERY_KEY
        query = data.fetch(:query)
        query.context.namespace(self.class).merge!(
          start_time: Time.now.utc,
          start_time_nanos: Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond),
          tree: ApolloTracing::TraceTree.new
        )

        result = yield
      when SYNC_LAZY_QUERY_RESULT_KEY
        # Note all query results are synced even if they're not lazy
        result = yield

        end_time_nanos = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)

        query = data.fetch(:query)
        trace = ApolloTracing::Proto::Trace.new(details: ApolloTracing::Proto::Trace::Details.new)
        trace.start_time = to_proto_timestamp(query.context.namespace(self.class).fetch(:start_time))
        trace.duration_ns = end_time_nanos - query.context.namespace(self.class).fetch(:start_time_nanos)
        trace.end_time = to_proto_timestamp(Time.now.utc)
        trace.root = query.context.namespace(self.class).fetch(:tree).root

        # TODO: Fill out Trace::Details? Requires removing sensitive data

        # Give consumers a chance to fill out additional details in the trace
        # like Trace::HTTP and client*
        trace_prepare.call(trace, query)

        @trace_channel.send("# #{query.operation_name || '-'}\n#{query_signature.call(query)}", trace)
      when EXECUTE_FIELD_KEY
        # TODO: See https://graphql-ruby.org/api-doc/1.9.3/GraphQL/Tracing. Different args are passed when
        # using the interpreter runtime
        start_time_nanos = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)
        result = yield
        end_time_nanos = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)

        # TODO: Handle errors

        if data.include?(:context)
          context = data.fetch(:context)
          field_name = context.field.graphql_name
          field_type = context.field.type.to_s
          parent_name = context.parent_type.graphql_name
          path = context.path
        else
          context = data.fetch(:query).context
          field_name = data.fetch(:field).graphql_name
          field_type = data.fetch(:field).type.unwrap.graphql_name
          parent_name = data.fetch(:owner).graphql_name
          path = data.fetch(:path)
        end

        context.namespace(self.class).fetch(:tree).add(
          path: path,
          parent_type: parent_name,
          field_name: field_name,
          field_type: field_type,
          start_time: start_time_nanos - context.namespace(self.class).fetch(:start_time_nanos),
          end_time: end_time_nanos - context.namespace(self.class).fetch(:start_time_nanos)
        )
      when SYNC_LAZY_FIELD_RESULT_KEY
        # Note only lazy field results are synced

        result = yield
        end_time_nanos = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)

        # Update the end time of the lazy field
        if data.include?(:context)
          context = data.fetch(:context)
          path = context.path
        else
          context = data.fetch(:query).context
          path = data.fetch(:path)
        end

        trace = context.namespace(self.class).fetch(:tree).node(path)
        trace.end_time = end_time_nanos - context.namespace(self.class).fetch(:start_time_nanos)

        # TODO: Handle errors
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
