require "test_helper"

class Sequel::PackerTest < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil ::Sequel::Packer::VERSION
  end

  class UserPacker < Sequel::Packer
    field :id
    field :name
  end

  def test_it_packs_basic_models
    paul = User.create(name: 'Paul')
    julius = User.create(name: 'Julius')

    packed_users = UserPacker.new.pack(User.order(:id))

    assert_equal paul.id, packed_users[0][:id]
    assert_equal paul.name, packed_users[0][:name]
    assert_equal julius.id, packed_users[1][:id]
    assert_equal julius.name, packed_users[1][:name]
  end
end
