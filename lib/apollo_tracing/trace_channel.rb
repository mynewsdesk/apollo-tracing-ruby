# frozen_string_literal: true

require_relative 'proto'
require_relative 'upload_job'

require 'zlib'

module ApolloTracing
  class TraceChannel
    attr_reader :compress, :api_key, :debug_reports
    alias_method :debug_reports?, :debug_reports

    def initialize(report_header:, compress: nil, api_key: nil, debug_reports: nil)
      @report_header = report_header
      @compress = compress.nil? ? true : compress
      @api_key = api_key
    end

    def send(query_key, trace)
      encoded_trace = ApolloTracing::Proto::Trace.encode(trace)
      trace_report = ApolloTracing::Proto::FullTracesReport.new(header: @report_header)
      trace_report.traces_per_query[query_key] = ApolloTracing::Proto::Traces.new(
        # TODO: Figure out how to use the already encoded traces like Apollo
        # https://github.com/apollographql/apollo-server/blob/master/packages/apollo-engine-reporting-protobuf/src/index.js
        trace: [ApolloTracing::Proto::Trace.decode(encoded_trace)]
      )

      body = gzip(ApolloTracing::Proto::FullTracesReport.encode(trace_report))
      headers = { 
        'X-Api-Key' => api_key,
        'Content-Encoding' => 'gzip' 
      }

      ApolloTracing::UploadJob.perform_async(body, headers)
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
