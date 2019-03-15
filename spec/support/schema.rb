# frozen_string_literal: true

require 'graphql'
require 'apollo_tracing'

module Model
  def self.included(base)
    base.extend(ClassMethods)
  end

  def initialize(**options)
    options.each do |key, value|
      send("#{key}=", value)
    end
  end

  module ClassMethods
    def db
      @db ||= {}
    end

    def all
      @db.values
    end

    def next_id
      id = @next_id || 1
      @next_id = id + 1
      id
    end

    def create(**options)
      id = next_id
      db[id] = new(id: id, **options)
    end

    def find(id)
      db[id]
    end

    def first
      db.values.first
    end
  end
end

class User < Struct.new(:id, :name)
  include Model

  def posts
    Post.for_user(id)
  end
end

class Post < Struct.new(:id, :user_id, :title)
  include Model

  def self.for_user(user_id)
    all.select { |post| post.user_id == user_id }
  end
end

class PostType < GraphQL::Schema::Object
  field :id, Integer, null: false
  field :title, String, null: false
end

class UserType < GraphQL::Schema::Object
  field :id, Integer, null: false
  field :name, String, null: false
  field :posts, [PostType], null: false
end

class QueryType < GraphQL::Schema::Object
  field :user, UserType, null: false do
    argument :id, Integer, required: true
  end

  def user(id:)
    User.find(id)
  end
end

class TestSchema < GraphQL::Schema
  query QueryType
  use ApolloTracing
end
