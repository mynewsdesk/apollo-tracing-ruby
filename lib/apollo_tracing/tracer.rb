# frozen_string_literal: true

require 'rest-client'
require 'zlib'

require_relative 'api'
require_relative 'trace_tree'

module ApolloTracing
  class Tracer
    attr_reader :compress, :api_key

    def initialize(compress:, api_key:)
      @compress = compress
      @api_key = api_key
    end

    def enabled?
      !@api_key.nil?
    end

    def trace(key, data)
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
        # TODO: Fill out Trace::Details, Trace::HTTP, signature, client*

        # TODO: Fill these out properly and batch them
        trace_report = ApolloTracing::API::FullTracesReport.new(
          header: ApolloTracing::API::ReportHeader.new(
            hostname: Socket.gethostname,
            agent_version: 'ruby-tracer',
            schema_tag: 'current'
            # service: 'foobar'
            # service_version: 'current-4279-20160804T065423Z-5-g3cf0aa8',
            # runtime_version: 'Ruby 2.6.2',
            # uname: 'TBD',
            # schema_hash: '9f665a0e61b8d3a21449970d87fc7037bc2b97a9'
          )
        )
        # TODO: Normalize queries for appropriate signatures
        trace_report.traces_per_query["#{query.operation_name}\\#{query.query_string}"] =
          ApolloTracing::API::Traces.new(trace: [trace])

        puts JSON.pretty_generate(JSON.parse(trace_report.to_json))

        # TODO: Background this or use async i/o
        send_report(trace_report)
      elsif key == 'execute_field'
        # TODO: See https://graphql-ruby.org/api-doc/1.9.3/GraphQL/Tracing. Different args are passed to the
        # interpreter
        start_time_nanos = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)
        result = yield
        end_time_nanos = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)

        # TODO: Handle errors
        context = data.fetch(:context)
        context.fetch(:apollo_tracing).fetch(:tree).add(
          # TODO: Statically compute some of this?
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

    # TODO: Remove me
    RestClient.log = Logger.new(STDOUT)

    def send_report(report)
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
