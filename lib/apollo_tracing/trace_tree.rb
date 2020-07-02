# frozen_string_literal: true

module ApolloTracing
  class TraceTree
    ROOT_PATH = [].freeze

    attr_reader :nodes

    def initialize
      @nodes = {
        ROOT_PATH => ApolloTracing::Proto::Trace::Node.new
      }
    end

    def root
      node(ROOT_PATH)
    end

    def node(path)
      @nodes.fetch(path)
    end

    def add(path:, field_name:, field_type:, parent_type:, start_time:, end_time:)
      node = ApolloTracing::Proto::Trace::Node.new(
        field_name: field_name,
        type: field_type,
        parent_type: parent_type,
        start_time: start_time,
        end_time: end_time
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
