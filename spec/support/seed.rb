# frozen_string_literal: true

require_relative 'schema'

users = Array.new(2) { |i| User.create(name: "user#{i}") }
users.each do |user|
  Array.new(3) { |i| Post.create(user_id: user.id, title: "post#{i}") }
end
