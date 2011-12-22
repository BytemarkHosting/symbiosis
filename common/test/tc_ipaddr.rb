$: << "../lib/"
require 'symbiosis/ipaddr'
require 'test/unit'
require 'pp'

class TestIPAddr < Test::Unit::TestCase

  include Symbiosis

  def test_to_s
    #
    # We want to see the cidr mask if more than one IP is in our range.
    #
    assert_equal("1.2.3.4",    IPAddr.new("1.2.3.4/32").to_s)
    assert_equal("1.2.3.0/24", IPAddr.new("1.2.3.4/24").to_s)

    assert_equal("2001:dead:beef:cafe:1234::1", IPAddr.new("2001:dead:beef:cafe:1234::1/128").to_s)
    assert_equal("2001:dead:beef:cafe::/64",    IPAddr.new("2001:dead:beef:cafe:1234::1/64").to_s)
  end

  def test_equality
    assert_equal(IPAddr.new("1.2.3.4/24"), IPAddr.new("1.2.3.4/24"))
    assert_not_equal(IPAddr.new("1.2.3.4/24"), IPAddr.new("1.2.3.4/32"))

    assert_equal(IPAddr.new("2001:dead:beef:cafe:1234::1/64"), IPAddr.new("2001:dead:beef:cafe:1234::1/64"))
    assert_not_equal(IPAddr.new("2001:dead:beef:cafe:1234::1/64"), IPAddr.new("2001:dead:beef:cafe:1234::1/128"))

  end

  
end






