# frozen_string_literal: true

require_relative 'api/apollo_pb'

module ApolloTracing
  API = ::Mdg::Engine::Proto

  module API
    URL = 'https://engine-report.apollodata.com/api/ingress/traces'
  end
end
