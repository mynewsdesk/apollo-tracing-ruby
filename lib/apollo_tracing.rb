# frozen_string_literal: true

require 'graphql'
require 'apollo_tracing/tracer'
require 'apollo_tracing/version'

module ApolloTracing
  def self.use(schema, **options)
    tracer = ApolloTracing::Tracer.new(**options)
    schema.tracer(tracer)
  end
end
