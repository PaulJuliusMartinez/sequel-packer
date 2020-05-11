DB = Sequel.sqlite

DB.create_table(:users) do
  primary_key :id
  String :name, null: false
end

DB.create_table(:posts) do
  primary_key :id
  foreign_key :author_id, :users, null: false, on_delete: :cascade
  String :title
  String :content
end

DB.create_table(:comments) do
  primary_key :id
  foreign_key :commenter_id, :users, null: false, on_delete: :cascade
  foreign_key :post_id, :posts, null: false, on_delete: :cascade
  foreign_key :parent_id, :comments, on_delete: :cascade
  String :content
end

DB.create_table(:likes) do
  primary_key :id
  foreign_key :liker_id, :users, null: false, on_delete: :cascade
  foreign_key :post_id, :posts
  foreign_key :comment_id, :comments
end

class User < Sequel::Model(:users)
  one_to_many :posts, key: :author_id, class: :Post
  one_to_many :likes, key: :liker_id, class: :Like
  many_to_many(
    :liked_posts,
    join_table: :likes,
    left_key: :liker_id,
    right_key: :post_id,
    class: :Post,
  )
end

class Post < Sequel::Model(:posts)
  many_to_one :author, key: :author_id, class: :User
  one_to_many :comments, key: :post_id, class: :Comment
  one_to_many :likes, key: :post_id, class: :Like
end

class Comment < Sequel::Model(:comments)
  many_to_one :commenter, key: :commenter_id, class: :User
  many_to_one :post, key: :post_id, class: :Post
  many_to_one :parent, key: :parent_id, class: :Comment
end

class Like < Sequel::Model(:likes)
  many_to_one :liker, key: :liker_id, class: :User
  many_to_one :post, key: :post_id, class: :Post
  many_to_one :comment, key: :comment_id, class: :Comment
end
