require "test_helper"

class Sequel::Packer::EagerHashTest < Minitest::Test
  Lib = Sequel::Packer::EagerHash

  ##################################
  # Tests for normalize_eager_args #
  ##################################

  def test_normalize_eager_hash_basic
    assert_equal({}, Lib.normalize_eager_args)

    assert_equal(
      {assoc: nil},
      Lib.normalize_eager_args(:assoc),
    )

    assert_equal(
      {a1: nil, a2: nil, a3: nil, a4: nil},
      Lib.normalize_eager_args(:a1, [:a2], [[:a3, :a4]]),
    )

    assert_equal(
      {assoc1: nil, assoc2: {nested_assoc: nil}},
      Lib.normalize_eager_args(:assoc1, assoc2: :nested_assoc),
    )

    assert_equal(
      {a1: {a2: {a3: {a4: nil, a5: nil}}}},
      Lib.normalize_eager_args(a1: {a2: {a3: [:a4, :a5]}}),
    )
  end

  def test_normalize_eager_hash_with_procs
    eager_proc = (proc {|ds| ds})

    assert_equal(
      {assoc: {eager_proc => nil}},
      Lib.normalize_eager_args(assoc: eager_proc),
    )

    assert_equal(
      {a: {eager_proc => {a2: nil, a3: nil}}, b: {eager_proc => nil}},
      Lib.normalize_eager_args(a: {eager_proc => [:a2, :a3]}, b: eager_proc),
    )
  end

  def test_mixed_proc_error
    assert_raises(Lib::MixedProcHashError) do
      Lib.normalize_eager_args(a: {b: :c, (proc {|ds| ds}) => :d})
    end
  end

  def test_multiple_proc_keys_error
    proc1 = (proc {|ds| ds})
    proc2 = (proc {|ds| ds})

    assert_raises(Lib::MultipleProcKeysError) do
      Lib.normalize_eager_args(a: {proc1 => :b, proc2 => :c})
    end
  end

  def test_nested_eager_procs_error
    proc1 = (proc {|ds| ds})
    proc2 = (proc {|ds| ds})

    assert_raises(Lib::NestedEagerProcsError) do
      Lib.normalize_eager_args(a: {proc1 => proc2})
    end

    assert_raises(Lib::NestedEagerProcsError) do
      Lib.normalize_eager_args(a: {proc1 => {proc2 => :c}})
    end
  end

  ###################
  # Tests for merge #
  ###################

  def test_merge_basic
    h1 = Lib.normalize_eager_args(:a)
    h2 = Lib.normalize_eager_args(:b)

    merged = Lib.merge(h1, h2)

    assert_equal({a: nil}, h1)
    assert_equal({b: nil}, h2)
    assert_equal({a: nil, b: nil}, merged)

    h3 = Lib.normalize_eager_args(a: [:a1, :a2], b: :b1)
    h4 = Lib.normalize_eager_args(a: {a2: :a21}, c: nil)

    merged = Lib.merge(h3, h4)

    assert_equal({a: {a1: nil, a2: nil}, b: {b1: nil}}, h3)
    assert_equal({a: {a2: {a21: nil}}, c: nil}, h4)
    assert_equal({a: {a1: nil, a2: {a21: nil}}, b: {b1: nil}, c: nil}, merged)
  end

  def test_merge_with_proc_in_hash1
    eager_proc = (proc {|ds| ds})

    h1 = Lib.normalize_eager_args(a: eager_proc)
    h2 = Lib.normalize_eager_args(:a)
    merged = Lib.merge(h1, h2)

    assert_equal({a: {eager_proc => nil}}, h1)
    assert_equal({a: nil}, h2)
    assert_equal({a: {eager_proc => nil}}, merged)

    h3 = Lib.normalize_eager_args(a: eager_proc)
    h4 = Lib.normalize_eager_args(a: [:b, c: :d])
    merged = Lib.merge(h3, h4)

    assert_equal({a: {eager_proc => nil}}, h3)
    assert_equal({a: {b: nil, c: {d: nil}}}, h4)
    assert_equal({a: {eager_proc => {b: nil, c: {d: nil}}}}, merged)

    h5 = Lib.normalize_eager_args(a: {eager_proc => :b})
    h6 = Lib.normalize_eager_args(a: [:c, :d])
    merged = Lib.merge(h5, h6)

    assert_equal({a: {eager_proc => {b: nil}}}, h5)
    assert_equal({a: {c: nil, d: nil}}, h6)
    assert_equal({a: {eager_proc => {b: nil, c: nil, d: nil}}}, merged)
  end

  def test_merge_with_proc_in_hash2
    eager_proc = (proc {|ds| ds})

    h1 = Lib.normalize_eager_args(:a)
    h2 = Lib.normalize_eager_args(a: eager_proc)
    merged = Lib.merge(h1, h2)

    assert_equal({a: nil}, h1)
    assert_equal({a: {eager_proc => nil}}, h2)
    assert_equal({a: {eager_proc => nil}}, merged)

    h3 = Lib.normalize_eager_args(a: [:b, c: :d])
    h4 = Lib.normalize_eager_args(a: eager_proc)
    merged = Lib.merge(h3, h4)

    assert_equal({a: {b: nil, c: {d: nil}}}, h3)
    assert_equal({a: {eager_proc => nil}}, h4)
    assert_equal({a: {eager_proc => {b: nil, c: {d: nil}}}}, merged)

    h5 = Lib.normalize_eager_args(a: [:c, :d])
    h6 = Lib.normalize_eager_args(a: {eager_proc => :b})
    merged = Lib.merge(h5, h6)

    assert_equal({a: {c: nil, d: nil}}, h5)
    assert_equal({a: {eager_proc => {b: nil}}}, h6)
    assert_equal({a: {eager_proc => {b: nil, c: nil, d: nil}}}, merged)
  end

  def test_merge_two_procs
    even = (proc {|arr| arr.select(&:even?)})
    positive = (proc {|arr| arr.select(&:positive?)})
    nums = [-2, -1, 1, 2]

    h1 = Lib.normalize_eager_args(a: even)
    h2 = Lib.normalize_eager_args(a: positive)
    merged = Lib.merge(h1, h2)

    new_proc = merged[:a].keys[0]
    assert_equal({a: {even => nil}}, h1)
    assert_equal({a: {positive => nil}}, h2)
    assert_equal [2], new_proc.call(nums)

    h3 = Lib.normalize_eager_args(a: {even => [{b: :b1}, :c]})
    h4 = Lib.normalize_eager_args(a: {positive => {b: :b2, d: :e}})
    merged = Lib.merge(h3, h4)

    new_proc = merged[:a].keys[0]
    assert_equal({a: {even => {b: {b1: nil}, c: nil}}}, h3)
    assert_equal({a: {positive => {b: {b2: nil}, d: {e: nil}}}}, h4)
    assert_equal(
      {a: {new_proc => {b: {b1: nil, b2: nil}, c: nil, d: {e: nil}}}},
      merged,
    )
    assert_equal [2], new_proc.call(nums)
  end
end
