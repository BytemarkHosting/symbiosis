#!/usr/bin/ruby 

require 'test/unit'
require 'symbiosis/host'
require 'symbiosis/ipaddr'

class HostTest < Test::Unit::TestCase

  include Symbiosis

  def setup

  end

  def teardown
  end

  #####
  #
  # Tests
  #
  #####

  def test_is_bytemark_ip?
    assert(Host.is_bytemark_ip?(IPAddr.new("80.68.80.24")))
    assert(!Host.is_bytemark_ip?(IPAddr.new("1.2.3.4")))
    assert(!Host.is_bytemark_ip?(IPAddr.new("80.68.64.0/19")))

    assert(Host.is_bytemark_ip?(IPAddr.new("2001:41c8::1/64")))
    assert(!Host.is_bytemark_ip?(IPAddr.new("2001:fa8::1/128")))
    assert(!Host.is_bytemark_ip?(IPAddr.new("2001:41c0::/31")))
  end
  
  def test_ip_addresses
    #
    # TODO
    #
    puts Host.ip_addresses if $DEBUG
  end
  
  def test_ipv4_addresses
    #
    # TODO
    #
    puts Host.ipv4_addresses if $DEBUG
  end
  
  def test_ipv6_addresses
    #
    # TODO
    #
    puts Host.ipv6_addresses if $DEBUG
  end

  def test_ipv6_ranges
    #
    # TODO
    #
    puts Host.ipv6_ranges if $DEBUG
  end
  
  def test_primary_ip
    #
    # TODO
    #
    puts Host.primary_ip if $DEBUG
  end
  
  def test_primary_bytemark_ip
    #
    # TODO
    #
    puts Host.primary_bytemark_ip if $DEBUG
  end

  def test_backup_spaces
    ip = Resolv.getaddress "example.vm.bytemark.co.uk"
    assert_equal(%w(example.backup.bytemark.co.uk), Host.backup_spaces(ip))
  end

  def test_primary_backup_space
    #
    # TODO
    #
  end

  def test_primary_interface
    #
    # TODO
    #
  end

  def test_add_ip
    #
    # TODO
    #
  end

end
