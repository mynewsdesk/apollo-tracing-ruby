# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'apollo_tracing'

require 'rspec'
require 'json_spec'

Dir["#{__dir__}/support/**/*.rb"].sort.each { |f| require f }


RSpec.configure do |config|
  config.include JsonSpec::Helpers
end
