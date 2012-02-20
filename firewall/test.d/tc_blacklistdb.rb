$: << "../lib/"
require 'symbiosis/firewall/blacklist_db'
require 'test/unit'
require 'ipaddr'
require 'fileutils'
require 'tempfile'

class TestBlacklistDb < Test::Unit::TestCase

  include Symbiosis::Firewall

  def setup
    @fn = Tempfile.new("blacklistdb-")
    @fn.close(false)
    @db = BlacklistDB.new(@fn.path)
  end

  def teardown
    unless $DEBUG
      File.unlink(@fn) if File.exists?(@fn)
    else
      FileUtils.move(@fn.path, @fn.path+"-saved")
      puts "BlacklistDB saved in #{@fn.path}-saved"
    end
  end

  def test_ipv4
    timestamp = Time.now.to_i 
    ip = "1.2.3.4"

    
    5.times do
      @db.set_count_for(ip, 1, timestamp += 1)
    end

    assert_equal(5, @db.get_count_for(ip, timestamp - 5))
  end

  def test_ipv6
    timestamp = Time.now.to_i
    ip = IPAddr.new("2001:41c8:1:12:123::23/64")

    5.times do
      @db.set_count_for(ip, 1, timestamp += 1)
    end

    assert_equal(5, @db.get_count_for(ip, timestamp - 5))
  end

  
end





