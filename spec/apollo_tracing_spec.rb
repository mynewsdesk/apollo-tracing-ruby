# frozen_string_literal: true

describe ApolloTracing do
  specify do
    query = <<~GRAPHQL
      query($userId: Int!) {
        user(id: $userId) {
          id
          name
          posts {
            id
            title
          }
        }
      }
    GRAPHQL

    user = User.first
    expected = {
      data: {
        user: {
          id: user.id,
          name: user.name,
          posts: user.posts.map do |post|
            { id: post.id, title: post.title }
          end
        }
      }
    }.to_json
    result = execute_query(query, variables: { userId: user.id })
    expect(result.to_h.to_json).to be_json_eql(expected)
  end

  def execute_query(query, variables: {}, context: {})
    TestSchema.execute(
      query,
      context: context,
      variables: JSON.parse(variables.to_json)
    )
  end
end
