$: << "../lib/"
require 'symbiosis/firewall/pattern'
require 'test/unit'
require 'pp'

class TestPattern < Test::Unit::TestCase
  include Symbiosis::Firewall

  def setup
  end

  def teardown
  end

  def test_load
    patt = Pattern.new("pattern.d/openssh.patterns")
    pp patt
  end

  
  def test_apply
    lines = File.readlines 'log/auth.log'
    patt = Pattern.new("pattern.d/openssh.patterns")
    pp patt.apply(lines)

  end


end



