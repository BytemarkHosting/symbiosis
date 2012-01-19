$:.unshift "../lib"

require 'test/unit'
require 'systemexit'

class TestSystemExit < Test::Unit::TestCase

  def test_success
    err = SystemExit.new(64)
    assert(!err.success?, "#{err.to_s} (#{err.to_i}) should not return as success")
    
    err = SystemExit.new(0)
    assert(err.success?, "#{err.to_s} (#{err.to_i}) should return as success")
  end

  def test_to_s
    err = SystemExit.new(0)
    assert_kind_of(String, err.to_s)
    assert_equal("Success", err.to_s)

    err = SystemExit.new(71)
    assert_kind_of(String, err.to_s)
    assert_equal("System error", err.to_s)
  end

  def test_to_i
    err = SystemExit.new(0)
    assert_kind_of(Integer, err.to_i)
    assert_equal(0, err.to_i)

    err = SystemExit.new(65)
    assert_kind_of(Integer, err.to_i)
    assert_equal(65, err.to_i)
  end

end

