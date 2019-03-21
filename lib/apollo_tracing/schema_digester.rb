# frozen_string_literal: true

require 'digest'

module ApolloTracing
  module SchemaDigester
    extend self

    def digest(schema)
      intropsection_result = normalize(schema.as_json.dig('data', '__schema'))
      Digest::SHA512.hexdigest(intropsection_result.to_json)
    end

    private

    # This performs the same normalization used by the https://github.com/epoberezkin/fast-json-stable-stringify
    # node module that Apollo uses
    def normalize(value)
      if value.is_a?(Hash)
        value.keys.sort.each_with_object({}) do |key, result|
          result[key] = normalize(value[key])
        end
      elsif value.is_a?(Array)
        value.map { |element| normalize(element) }
      else
        value
      end
    end
  end
end
