# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rspec/core/rake_task'

RSpec::Core::RakeTask.new(:spec)

task default: :spec

task :generate_schema do
  require_relative 'spec/support/schema'
  require 'fileutils'

  file = ENV.fetch('file')
  dir = File.dirname(file) || Dir.pwd
  FileUtils.makedirs(dir)
  IO.write(file, TestSchema.to_definition)
end
