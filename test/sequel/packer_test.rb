require "test_helper"

class Sequel::PackerTest < Minitest::Test
  # Run tests in Sequel transaction.
  def run(*args, &block)
    DB.transaction(:rollback=>:always, :auto_savepoint=>true) {super}
  end

  def test_that_it_has_a_version_number
    refute_nil ::Sequel::Packer::VERSION
  end

  class BasicFieldPacker < Sequel::Packer
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
