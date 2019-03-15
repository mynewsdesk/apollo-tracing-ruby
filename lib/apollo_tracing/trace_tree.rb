# frozen_string_literal: true

require_relative 'api'

module ApolloTracing
  class TraceTree
    ROOT_PATH = [].freeze

    attr_reader :nodes

    def initialize
      @nodes = {
        ROOT_PATH => ApolloTracing::API::Trace::Node.new
      }
    end

    def root
      @nodes.fetch(ROOT_PATH)
    end

    def add(path:, field:, parent_type:, start_time_offset:, end_time_offset:)
      node = ApolloTracing::API::Trace::Node.new(
        field_name: field.graphql_name,
        type: field.type.to_s,
        parent_type: parent_type.graphql_name,
        start_time: start_time_offset,
        end_time: end_time_offset
      )

      @nodes[path] = node

      # Create ancestor nodes as necessary
      parent_path = path.take(path.size - 1)
      until nodes.include?(parent_path)
        parent = ::Mdg::Engine::Proto::Trace::Node.new(
          index: parent_path.last
        )
        parent.child << node

        node = parent
        parent_path = parent_path.take(parent_path.size - 1)
      end

      nodes[parent_path].child << node
    end
  end
end
