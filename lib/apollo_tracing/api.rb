# frozen_string_literal: true

require 'net/http'
require 'openssl'
require 'uri'
require 'zlib'

require_relative 'api/apollo_pb'

module ApolloTracing
  API = ::Mdg::Engine::Proto

  module API
    extend self

    APOLLO_URL = 'https://engine-report.apollodata.com/api/ingress/traces'
    APOLLO_URI = ::URI.parse(APOLLO_URL)

    def upload(report, compress: true, api_key:)
      body = compress ? gzip(report.class.encode(report)) : report.class.encode(report)
      headers = { 'X-Api-Key' => api_key }
      headers['Content-Encoding'] = 'gzip' if compress
      result = Net::HTTP.post(APOLLO_URI, body, headers)

      if result.is_a?(Net::HTTPServerError)
        # TODO: Retry with exponential backoff
        ApolloTracing.logger.warning("Failed to send trace report: #{result.message} (#{result.code}) - #{result.body}")
      elsif !result.is_a?(Net::HTTPSuccess)
        ApolloTracing.logger.warning("Failed to send trace report: #{result.message} (#{result.code}) - #{result.body}")
      end
    rescue IOError, SocketError, SystemCallError, OpenSSL::OpenSSLError => e
      # TODO: Retry with exponential backoff
      ApolloTracing.logger.warning("Failed to send trace report: #{e.class} - #{e.message}")
    end

    private

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
