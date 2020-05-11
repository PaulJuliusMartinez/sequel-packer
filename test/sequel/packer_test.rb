require "test_helper"

class Sequel::PackerTest < Minitest::Test
  # Run tests in Sequel transaction.
  def run(*args, &block)
    DB.transaction(:rollback=>:always, :auto_savepoint=>true) {super}
  end

  def test_that_it_has_a_version_number
    refute_nil ::Sequel::Packer::VERSION
  end

  class DummyUserPacker < Sequel::Packer
    model User
  end

  class DummyPostPacker < Sequel::Packer
    model Post
  end

  ############################################
  # Validation of arguments passed to field. #
  ############################################

  def test_raises_if_model_not_yet_declared
    assert_raises(Sequel::Packer::ModelNotYetDeclaredError) do
      Class.new(Sequel::Packer) do
        field :id
      end
    end
  end

  def assert_packer_declaration_raises(model_klass, &block)
    assert_raises(Sequel::Packer::FieldArgumentError) do
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
    err = assert_packer_declaration_raises(User) do
      field :posts
    end
    assert_includes err.message, 'must also pass a Sequel::Packer class'
  end

  def test_association_doesnt_exist
    err = assert_packer_declaration_raises(User) do
      field :recent_posts, DummyPostPacker
    end
    assert_includes err.message, 'association recent_posts does not exist'
  end

  def test_association_packer_class_isnt_a_packer
    err = assert_packer_declaration_raises(User) do
      field :posts, String
    end
    assert_includes err.message, 'is not a subclass of Sequel::Packer'
  end

  def test_association_packer_class_model_doesnt_match_association_model
    err = assert_packer_declaration_raises(User) do
      field :posts, DummyUserPacker
    end
    assert_includes err.message, "doesn't match model for the posts association"
  end

  def test_multiple_arguments_with_block
    err = assert_packer_declaration_raises(User) do
      field(:posts, DummyPostPacker) {|_model|}
    end
    assert_includes err.message, 'passing a block to Sequel::Packer::field'
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
end
