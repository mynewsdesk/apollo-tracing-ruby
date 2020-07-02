# frozen_string_literal: true

require 'graphql'
require 'logger'

require 'apollo_tracing/tracer'
require 'apollo_tracing/version'

module ApolloTracing
  extend self

  attr_accessor :logger

  # TODO: Initialize this to Rails.logger in a Railtie
  self.logger = Logger.new(STDOUT)

  def use(schema, **options)
    schema.tracer(ApolloTracing::Tracer.new(**options))
  end
  
end
