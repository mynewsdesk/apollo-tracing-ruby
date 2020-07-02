# frozen_string_literal: true

lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'apollo_tracing/version'

Gem::Specification.new do |spec|
  spec.name          = 'apollo-tracing'
  spec.version       = ApolloTracing::VERSION
  spec.authors       = ['Reginald Suh', 'Evgeny Li']
  spec.email         = ['evgeny.li@universe.com', 'rsuh@edu.uwaterloo.ca']

  spec.summary       = 'Ruby implementation of GraphQL trace data in the Apollo Tracing format.'
  spec.description   = 'Ruby implementation of GraphQL trace data in the Apollo Tracing format.'
  spec.homepage      = 'https://github.com/uniiverse/apollo-tracing-ruby'
  spec.license       = 'MIT'

  spec.files         = `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  spec.bindir        = 'exe'
  spec.require_paths = ['lib']

  spec.required_ruby_version = '>= 2.4.0'

  spec.add_runtime_dependency 'sidekiq-pro'
  spec.add_runtime_dependency 'concurrent-ruby'
  spec.add_runtime_dependency 'google-protobuf'
  spec.add_runtime_dependency 'graphql', '>= 1.9', '< 2'

  spec.add_development_dependency 'bundler', '~> 2.0'
  spec.add_development_dependency 'dotenv'
  spec.add_development_dependency 'json_spec'
  spec.add_development_dependency 'rake', '~> 12.0'
  spec.add_development_dependency 'rspec', '~> 3.8'
  spec.add_development_dependency 'salsify_rubocop', '~> 0.60.0'
end
