
$: << "../lib/"
require 'symbiosis/firewall/directory'
require 'test/unit'
require 'pp'

class TestFirewallIPDirectory < Test::Unit::TestCase

  include Symbiosis::Firewall

  def test_to_s
    list = IPListDirectory.new("ips.d","incoming","whitelist" )
    Template.directories = ["rule.d"]
    puts list.to_s
  end

  
end





