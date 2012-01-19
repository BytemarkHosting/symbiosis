$:.unshift  "../lib/" if File.directory?("../lib")

require 'symbiosis/ipaddr'
require 'test/unit'

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

  def test_broadcast
    assert_equal(IPAddr.new("1.2.3.127/32"),IPAddr.new("1.2.3.4/25").broadcast)
    assert_equal(IPAddr.new("2001:dead:beef:cafe:ffff:ffff:ffff:ffff/128"),IPAddr.new("2001:dead:beef:cafe::/64").broadcast)
  end

  def test_network
    assert_equal(IPAddr.new("1.2.3.0/32"),IPAddr.new("1.2.3.4/25").network)
    assert_equal(IPAddr.new("2001:dead:beef:cafe:0000:0000:0000:0000/128"),IPAddr.new("2001:dead:beef:cafe::/64").network)
  end

  def test_include
    assert(IPAddr.new("1.2.3.4/24").include?(IPAddr.new("1.2.3.4")))
    assert(!IPAddr.new("1.2.3.4/24").include?(IPAddr.new("1.2.4.4")))

    #
    # This shouldn't take forever to establish.
    # 
    assert(IPAddr.new("2000::/3").include?(IPAddr.new("2001:dead:beef:cafe:ffff:ffff:ffff:ffff")))
    assert(!IPAddr.new("2001:dead:beef:cafe::/64").include?(IPAddr.new("2001:dead:beef:caff:ffff:ffff:ffff:ffff")))

  end

  def test_range_to_s
    assert_equal("1.2.3.0/255.255.255.128",IPAddr.new("1.2.3.4/25").range_to_s)
    #
    # Not sure this is correct for IPv6..
    #
    assert_equal("2001:dead:beef:ca00:0000:0000:0000:0000/ffff:ffff:ffff:ff00:0000:0000:0000:0000",IPAddr.new("2001:dead:beef:cafe::/56").range_to_s)

  end

  def test_cidr_mask
    #
    # Couple of examples.
    #
    assert_equal(31, IPAddr.new("1.2.3.4/31").cidr_mask)
    assert_equal(61, IPAddr.new("2001:1af::/61").cidr_mask)
  end

  def test_from_i
    #
    # the number 1 can be one of two addresses, default to IPv4
    #
    assert_equal(IPAddr.new("0.0.0.1"), IPAddr.from_i(1))
    assert_equal(IPAddr.new("0.0.0.1"), IPAddr.from_i(1, Socket::AF_INET))
    assert_equal(IPAddr.new("::1"),     IPAddr.from_i(1, Socket::AF_INET6))

    #
    # More tests.
    #
  end
  
end

