# frozen_string_literal: true

require 'graphql'
require 'apollo_tracing/tracer'
require 'apollo_tracing/version'

module ApolloTracing
  def self.use(schema, compress: true, api_key: ENV['ENGINE_API_KEY'])
    tracer = ApolloTracing::Tracer.new(compress: compress, api_key: api_key)
    if tracer.enabled?
      puts 'Enabling Apollo tracing...'
      schema.tracer(tracer)
    end
  end
end
