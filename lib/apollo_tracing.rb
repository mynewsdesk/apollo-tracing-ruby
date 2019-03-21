# frozen_string_literal: true

require 'graphql'
require 'logger'
require 'apollo_tracing/tracer'
require 'apollo_tracing/version'

module ApolloTracing
  class << self
    attr_accessor :logger
  end

  # TODO: Initialize this to Rails.logger in a Railtie
  self.logger = Logger.new(STDOUT)

  def self.use(schema, **options)
    @tracer = ApolloTracing::Tracer.new(**options)
    schema.tracer(@tracer)

    trap('SIGINT') do
      Thread.new { shutdown }
    end

    @tracer.start_uploader
  end

  def self.synchronize
    @tracer.synchronize_uploads if @tracer
  end

  def self.shutdown
    @tracer.shutdown_uploader if @tracer
  end
end
