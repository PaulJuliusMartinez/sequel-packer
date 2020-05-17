require "test_helper"

class Sequel::PackerTest < Minitest::Test
  # Run tests in Sequel transaction.
  def run(*args, &block)
    DB.transaction(:rollback=>:always, :auto_savepoint=>true) {super}
  end

  def test_that_it_has_a_version_number
    refute_nil ::Sequel::Packer::VERSION
  end

  ######################
  # Some basic packers #
  ######################

  class UserIdPacker < Sequel::Packer
    model User
    field :id
  end

  class PostIdPacker < Sequel::Packer
    model Post
    field :id
  end

  class CommentIdPacker < Sequel::Packer
    model Comment
    field :id
  end

  ############################################
  # Validation of arguments passed to field. #
  ############################################

  AssociationDoesNotExist = Sequel::Packer::AssociationDoesNotExistError
  InvalidAssociation = Sequel::Packer::InvalidAssociationPackerError
  UnknownTrait = Sequel::Packer::UnknownTraitError

  def test_raises_if_model_not_yet_declared
    assert_raises(Sequel::Packer::ModelNotYetDeclaredError) do
      Class.new(Sequel::Packer) do
        field :id
      end
    end
  end

  def assert_packer_declaration_raises(model_klass, err_class=nil, &block)
    assert_raises(err_class || Sequel::Packer::FieldArgumentError) do
      klass = Class.new(Sequel::Packer)
      klass.send(:model, model_klass) if model_klass
      klass.class_eval(&block)
    end
  end

  def test_field_name_must_be_a_symbol_or_string
    err = assert_packer_declaration_raises(User) do
      field 4
    end
    assert_includes err.message, 'Symbol'
    assert_includes err.message, 'String'
  end

  def test_block_for_field_doesnt_accept_correct_number_of_arguments
    err = assert_packer_declaration_raises(User) do
      field(:user) {}
    end
    assert_includes err.message, 'exactly one argument'

    err = assert_packer_declaration_raises(User) do
      field(:user) {|_, _|}
    end
    assert_includes err.message, 'exactly one argument'
  end

  def test_block_only_doesnt_accept_correct_number_of_arguments
    err = assert_packer_declaration_raises(User) do
      field {|_model|}
    end
    assert_includes err.message, 'exactly two arguments'
  end

  def test_association_field_doesnt_specify_packer
    err = assert_packer_declaration_raises(User, InvalidAssociation) do
      field :posts
    end
    assert_includes err.message, 'must also pass a Sequel::Packer class'
  end

  def test_association_doesnt_exist
    err = assert_packer_declaration_raises(User, AssociationDoesNotExist) do
      field :recent_posts, PostIdPacker
    end
    assert_includes err.message, 'association :recent_posts does not exist'
  end

  def test_association_packer_class_isnt_a_packer
    err = assert_packer_declaration_raises(User, InvalidAssociation) do
      field :posts, String
    end
    assert_includes err.message, 'is not a subclass of Sequel::Packer'
  end

  def test_association_packer_class_model_doesnt_match_association_model
    err = assert_packer_declaration_raises(User, InvalidAssociation) do
      field :posts, UserIdPacker
    end
    assert_includes err.message, "doesn't match model for the posts association"
  end

  def test_multiple_arguments_with_block
    err = assert_packer_declaration_raises(User) do
      field(:posts, PostIdPacker) {|_model|}
    end
    assert_includes err.message, 'passing a block to Sequel::Packer::field'
  end

  def test_association_field_trait_doesnt_exist
    err = assert_packer_declaration_raises(User, UnknownTrait) do
      field :posts, PostIdPacker, :fake_trait
    end
    assert_includes err.message, "Trait :fake_trait isn't defined"
    assert_includes err.message, 'PostIdPacker'
  end

  def test_trait_doesnt_exist
    err = assert_raises(ArgumentError, UnknownTrait) do
      UserIdPacker.new(:fake_trait)
    end
    assert_includes err.message, 'Unknown trait'
    assert_includes err.message, 'UserIdPacker'
    assert_includes err.message, ':fake_trait'
  end

  def test_redefine_trait
    err = assert_packer_declaration_raises(User, ArgumentError) do
      trait(:my_trait) {}
      trait(:my_trait) {}
    end
    assert_includes err.message, 'Trait :my_trait already defined'
  end

  def test_trait_no_block
    err = assert_packer_declaration_raises(User, ArgumentError) do
      trait(:no_block)
    end
    assert_includes err.message, 'Must give a block'
  end

  ######################################
  # Actual Packer functionality tests. #
  ######################################

  class BasicFieldPacker < Sequel::Packer
    model User

    field :id
    field :name
  end

  def test_it_packs_basic_fields
    paul = User.create(name: 'Paul')
    julius = User.create(name: 'Julius')

    packed_users = BasicFieldPacker.new.pack(User.order(:id))

    assert_equal paul.id, packed_users[0][:id]
    assert_equal paul.name, packed_users[0][:name]
    assert_equal julius.id, packed_users[1][:id]
    assert_equal julius.name, packed_users[1][:name]
  end

  class BlockFieldPacker < Sequel::Packer
    model User

    field(:id) {|model| model.id}
    field(:name, &:name)

    field do |model, hash|
      hash[:id_from_block] = model.id
      hash[:name_from_block] = model.name
    end
  end

  def test_it_packs_fields_defined_via_blocks
    paul = User.create(name: 'Paul')

    packed_user = BlockFieldPacker.new.pack(User.dataset)[0]

    assert_equal paul.id, packed_user[:id]
    assert_equal paul.name, packed_user[:name]
    assert_equal paul.id, packed_user[:id_from_block]
    assert_equal paul.name, packed_user[:name_from_block]
  end

  class BasicCommentPacker < Sequel::Packer
    model Comment
    field :id
    field :content
  end

  class PostWithCommentsPacker < Sequel::Packer
    model Post
    field :id
    field :title
    field :comments, BasicCommentPacker
  end

  def test_it_packs_associations
    user = User.create(name: 'Paul')
    post1 = Post.create(title: 'Post 1', author: user)
    post2 = Post.create(title: 'Post 2', author: user)
    comment1 = Comment.create(post: post1, commenter: user, content: 'A')
    comment2 = Comment.create(post: post1, commenter: user, content: 'B')
    comment3 = Comment.create(post: post2, commenter: user, content: 'C')

    packed_posts = PostWithCommentsPacker.new.pack(Post.order(:id))
    post1_comments = [comment1, comment2]
    packed_post1_comments = packed_posts[0][:comments]
    assert_equal 2, packed_post1_comments.length
    assert_equal(
      post1_comments.map(&:id),
      packed_post1_comments.map {|h| h[:id]}.sort,
    )
    assert_equal(
      post1_comments.map(&:content),
      packed_post1_comments.map {|h| h[:content]}.sort,
    )

    packed_post2_comments = packed_posts[1][:comments]
    assert_equal 1, packed_post2_comments.length
    assert_equal comment3.id, packed_post2_comments[0][:id]
    assert_equal comment3.content, packed_post2_comments[0][:content]
  end

  class UserWithPostsWithCommentsPacker < Sequel::Packer
    model User
    field :id
    field :name
    field :posts, PostWithCommentsPacker
  end

  def test_it_packs_nested_associations
    user = User.create(name: 'Paul')
    post1 = Post.create(title: 'Post 1', author: user)
    post2 = Post.create(title: 'Post 2', author: user)
    comment1 = Comment.create(post: post1, commenter: user, content: 'A')
    comment2 = Comment.create(post: post1, commenter: user, content: 'B')
    comment3 = Comment.create(post: post2, commenter: user, content: 'C')

    packed_users = UserWithPostsWithCommentsPacker.new.pack(User.dataset)
    assert_equal 1, packed_users.length

    packed_posts = packed_users[0][:posts]
    assert_equal [post1.id, post2.id], packed_posts.map {|p| p[:id]}.sort

    packed_post1 = packed_posts.find {|p| p[:id] == post1.id}
    packed_post2 = packed_posts.find {|p| p[:id] == post2.id}

    assert_equal(
      [comment1.id, comment2.id],
      packed_post1[:comments].map {|c| c[:id]}.sort,
    )
    assert_equal [comment3.id], packed_post2[:comments].map {|c| c[:id]}
  end

  class BasicTraitPacker < Sequel::Packer
    model Post

    field :id

    trait :author do
      field :author, UserIdPacker
    end

    trait :foobar do
      field(:foo) {|_| 'bar'}
    end
  end

  def test_basic_trait_usage
    user = User.create(name: 'Paul')
    Post.create(title: 'Post', author: user)

    packed_post = BasicTraitPacker.new.pack(Post.dataset)[0]
    refute packed_post.key?(:foobar)
    refute packed_post.key?(:author)

    packed_post_with_author =
      BasicTraitPacker.new(:author).pack(Post.dataset)[0]
    refute packed_post_with_author.key?(:foobar)
    assert_equal({id: user.id}, packed_post_with_author[:author])

    packed_post_with_foobar =
      BasicTraitPacker.new(:foobar).pack(Post.dataset)[0]
    refute packed_post_with_foobar.key?(:author)
    assert_equal 'bar', packed_post_with_foobar[:foo]

    packed_post_with_traits =
      BasicTraitPacker.new(:author, :foobar).pack(Post.dataset)[0]
    assert_equal({id: user.id}, packed_post_with_traits[:author])
    assert_equal 'bar', packed_post_with_traits[:foo]
  end

  class CommentWithCommenterTraitPacker < Sequel::Packer
    model Comment
    field :id
    trait :commenter do
      field :commenter, UserIdPacker
    end
  end

  class NestedTraitPacker < Sequel::Packer
    model Post
    field :id
    trait :comments do
      field :comments, CommentWithCommenterTraitPacker, :commenter
    end
  end

  def test_nested_traits
    user = User.create(name: 'Paul')
    post = Post.create(title: 'Post', author: user)
    comment1 = Comment.create(post: post, commenter: user, content: 'A')
    comment2 = Comment.create(post: post, commenter: user, content: 'B')

    packed_post = NestedTraitPacker.new(:comments).pack(Post.dataset)[0]
    comments = packed_post[:comments]
    assert_equal [comment1.id, comment2.id], comments.map {|h| h[:id]}.sort
    comments.each do |comment|
      assert_equal({id: user.id}, comment[:commenter])
    end
  end

  #########################
  # Eager loading testing #
  #########################

  class UserTraitsPacker < Sequel::Packer
    model User
    trait(:posts) {field :posts, PostTraitsPacker}
    trait(:posts_with_comments) {field :posts, PostTraitsPacker, :comments}
    trait(:comments) {field :comments, CommentTraitsPacker}
    trait(:comments_with_likes_with_liker) do
      field :comments, CommentTraitsPacker, :likes_with_liker
    end
  end

  class PostTraitsPacker < Sequel::Packer
    model Post
    trait(:comments) {field :comments, CommentTraitsPacker}
    trait(:comments_with_commenters) {
      field :comments, CommentTraitsPacker, :commenter
    }
  end

  class LikeTraitsPacker < Sequel::Packer
    model Like
    trait(:liker) {field :liker, UserTraitsPacker}
  end

  class CommentTraitsPacker < Sequel::Packer
    model Comment
    trait(:commenter) {field :commenter, CommentTraitsPacker}
    trait(:likes) {field :likes, LikeTraitsPacker}
    trait(:likes_with_liker) {field :likes, LikeTraitsPacker, :liker}
  end

  def test_eager_hash
    assert_nil UserTraitsPacker.new.send(:eager_hash)

    assert_equal(
      {posts: nil},
      UserTraitsPacker.new(:posts).send(:eager_hash),
    )

    assert_equal(
      {
        posts: {comments: nil},
        comments: {likes: {liker: nil}},
      },
      UserTraitsPacker
        .new(:posts_with_comments, :comments_with_likes_with_liker)
        .send(:eager_hash),
    )
  end

  class QueryCounter
    attr_reader :count

    def info(query)
      @count ||= 0
      @count += 1
    end

    def error(_); end
  end

  def assert_n_queries(n)
    query_counter = QueryCounter.new
    DB.loggers << query_counter
    yield
    assert_equal n, query_counter.count
  ensure
    DB.loggers.pop
  end

  def test_eager_loading_occurs
    user1 = User.create(name: 'Paul')
    user2 = User.create(name: 'Julius')
    post1 = Post.create(author: user1)
    post2 = Post.create(author: user1)
    post3 = Post.create(author: user2)
    comment1 = Comment.create(commenter: user1, post: post1)
    comment2 = Comment.create(commenter: user2, post: post2)
    Comment.create(commenter: user2, post: post3)
    Like.create(liker: user1, post: post2)
    Like.create(liker: user2, post: post1, comment: comment1)
    Like.create(liker: user1, post: post2, comment: comment2)

    packer = UserTraitsPacker
      .new(:posts_with_comments, :comments_with_likes_with_liker)

    # users (1)
    # - posts (2)
    #   - comments (3)
    # - comments (4)
    #   - likes (5)
    #     - liker (6)
    assert_n_queries(6) {packer.pack(User.dataset)}

    # No query for users
    users = User.dataset.all
    assert_n_queries(5) {packer.pack(users)}

    # No query for users
    user = user1.refresh
    assert_n_queries(5) {packer.pack(user)}
  end

  #################
  # eager testing #
  #################

  class UserPostAndCommentCountPacker < Sequel::Packer
    model User

    field :id

    eager :posts
    field(:num_posts) {|user| user.posts.count}

    eager(comments: (proc {|ds| ds.where(Sequel.lit('id % 2 = 0'))}))
    field(:num_even_comments) {|user| user.comments.count}
  end

  def test_eager
    user = User.create(name: 'Paul')
    User.create(name: 'Julius')
    post = Post.create(author: user)
    Post.create(author: user)
    Comment.create(commenter: user, post: post)
    Comment.create(commenter: user, post: post)

    packed_users = nil
    # users (1)
    # - posts (2)
    # - comments (3)
    assert_n_queries(3) do
      packed_users = UserPostAndCommentCountPacker.new.pack(User.dataset)
    end

    packed_user = packed_users.find {|h| h[:id] == user.id}
    assert_equal 2, packed_user[:num_posts]
    assert_equal 1, packed_user[:num_even_comments]
  end

  class EagerTraitPacker < Sequel::Packer
    model User

    trait :posts_id_eq_0_mod_2 do
      eager(posts: (proc {|ds| ds.where(Sequel.lit('id % 2 = 0'))}))
      field :posts, PostIdPacker
    end

    trait :posts_id_eq_0_mod_3 do
      eager(posts: (proc {|ds| ds.where(Sequel.lit('id % 3 = 0'))}))
      field :posts, PostIdPacker
    end
  end

  def test_eager_in_traits
    user = User.create(name: 'Paul')
    6.times {Post.create(author: user)}

    packed_users = EagerTraitPacker.new(:posts_id_eq_0_mod_2).pack(User.dataset)
    assert_equal 3, packed_users[0][:posts].count

    packed_users = EagerTraitPacker.new(:posts_id_eq_0_mod_3).pack(User.dataset)
    assert_equal 2, packed_users[0][:posts].count

    packed_users = EagerTraitPacker
      .new(:posts_id_eq_0_mod_2, :posts_id_eq_0_mod_3)
      .pack(User.dataset)
    assert_equal 1, packed_users[0][:posts].count
  end

  ###################################################
  # set_association_packer/pack_association testing #
  ###################################################

  class SetAssociationPacker < Sequel::Packer
    model User

    field :id

    set_association_packer :posts, PostIdPacker
    field :most_recent_post do |user|
      pack_association(:posts, user.posts.max_by(&:id))
    end

    trait :even_comments do
      set_association_packer :comments, CommentIdPacker
      field :even_comments do |user|
        pack_association(
          :comments,
          user.comments.select {|c| c.id % 2 == 0},
        )
      end
    end
  end

  def test_set_association_packer_and_pack_association
    user = User.create(name: 'Paul')

    packed_user = SetAssociationPacker.new(:even_comments).pack(User.dataset)[0]
    assert_nil packed_user[:most_recent_post]
    assert_empty packed_user[:even_comments]

    Post.create(author: user)
    recent_post = Post.create(author: user)

    comment1 = Comment.create(commenter: user, post: recent_post)
    comment2 = Comment.create(commenter: user, post: recent_post)
    even_comment = [comment1, comment2].find {|c| c.id % 2 == 0}

    # Create some other users.
    3.times {|n| User.create(name: "User #{n}")}

    assert_n_queries(3) do
      packed_user = SetAssociationPacker
        .new(:even_comments)
        .pack(User.dataset.order(:id))[0]
    end

    assert_equal recent_post.id, packed_user[:most_recent_post][:id]
    assert_equal [{id: even_comment.id}], packed_user[:even_comments]
  end

  ######################
  # precompute testing #
  ######################

  class PrecomputedCommentPacker < Sequel::Packer
    model Comment

    precompute {|comments| @total_comments = comments.count}
    field(:precomputed_value) {|_| @total_comments}

    trait :precompute_trait do
      precompute {|comments| @comment_ids = comments.map(&:id).sort}
      field(:precomputed_trait_value) {|_| @comment_ids}
    end
  end

  class PrecomputedPostPacker < Sequel::Packer
    model Post

    precompute {|posts| @total_posts = posts.count}
    field(:precomputed_value) {|_| @total_posts}

    trait :precompute_trait do
      precompute {|posts| @post_ids = posts.map(&:id).sort}
      field(:precomputed_trait_value) {|_| @post_ids}
    end

    field :comments, PrecomputedCommentPacker, :precompute_trait
  end

  class PrecomputedUserPacker < Sequel::Packer
    model User

    precompute {|users| @total_users = users.count}
    field(:precomputed_value) {|_| @total_users}

    trait :precompute_trait do
      precompute {|users| @user_ids = users.map(&:id).sort}
      field(:precomputed_trait_value) {|_| @user_ids}
    end

    field :posts, PrecomputedPostPacker, :precompute_trait
  end

  def test_precompute
    users = 2.times.map {|n| User.create(name: "User #{n}")}
    posts = users.flat_map do |user|
      2.times.map {|n| Post.create(author: user)}
    end
    comments = posts.flat_map do |post|
      users.map.with_index do |user, n|
        Comment.create(commenter: user, post: post)
      end
    end

    packed_user = PrecomputedUserPacker
      .new(:precompute_trait)
      .pack(User.dataset)[0]
    assert_equal 2, packed_user[:precomputed_value]
    assert_equal users.map(&:id), packed_user[:precomputed_trait_value]

    packed_post = packed_user[:posts][0]
    assert_equal 4, packed_post[:precomputed_value]
    assert_equal posts.map(&:id), packed_post[:precomputed_trait_value]

    packed_comment = packed_post[:comments][0]
    assert_equal 8, packed_comment[:precomputed_value]
    assert_equal comments.map(&:id), packed_comment[:precomputed_trait_value]
  end
end
