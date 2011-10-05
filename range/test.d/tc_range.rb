#!/usr/bin/ruby 

# OK we're running this test locally
unless File.dirname( File.expand_path( __FILE__ ) ) == "/etc/symbiosis/test.d"
  ["../lib", "../../test/lib" ].each do |d|
    if File.directory?(d) 
      $: << d
    else
      raise Errno::ENOENT, d
    end
  end
end

require 'test/unit'
require 'symbiosis/range'

TMP_PATH = File.join("/tmp", "#{__FILE__}.#{$$}")

module Symbiosis
  class Range
    def self.do_system(cmd)
      filename = "cmd/#{cmd.gsub(/\W+/,'_')}"
      File.readlines(filename).join
    end
  end
end

class RangeTest < Test::Unit::TestCase

  def setup
  end

  def teardown
  end

  #####
  #
  # Helper methods
  #
  #####

  #####
  #
  # Tests
  #
  #####

  

  def test_is_bytemark_ip?
  end
  
  def test_ip_addresses
    pp Symbiosis::Range.ip_addresses
  end
  
  def test_ipv4_addresses
    pp Symbiosis::Range.ipv6_addresses
  end
  
  def test_ipv6_addresses
    pp Symbiosis::Range.ipv6_addresses
  end

  def test_ipv6_ranges
    pp Symbiosis::Range.ipv6_ranges
  end
  
  def test_primary_ip
  end
  
  def test_primary_bytemark_ip
  end

  def test_backup_spaces
  end

  def test_primary_backup_space
  end

end
