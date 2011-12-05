$: << "../lib/"
require 'symbiosis/firewall/ipaddr'
require 'test/unit'
require 'pp'

class TestIPAddr < Test::Unit::TestCase

  include Symbiosis::Firewall

  def test_to_s
    assert_equal("1.2.3.4/32", IPAddr.new("1.2.3.4/32").to_s)
    assert_equal("1.2.3.0/24", IPAddr.new("1.2.3.4/24").to_s)

    assert_equal("2001:dead:beef:cafe:1234::1/128",IPAddr.new("2001:dead:beef:cafe:1234::1/128").to_s)
    assert_equal("2001:dead:beef:cafe::/64",IPAddr.new("2001:dead:beef:cafe:1234::1/64").to_s)
  end

  def test_equality

    assert_equal(IPAddr.new("1.2.3.4/24"), IPAddr.new("1.2.3.4/24"))
  end

  
end






