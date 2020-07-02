require 'net/http'
require 'openssl'
require 'uri'

require 'sidekiq'

module ApolloTracing
  class UploadJob
    include Sidekiq::Worker

    APOLLO_URL = 'https://engine-report.apollodata.com/api/ingress/traces'
    APOLLO_URI = ::URI.parse(APOLLO_URL)

    def perform(body, headers)
      Net::HTTP.post(APOLLO_URI, body, headers)
    end
  end
end