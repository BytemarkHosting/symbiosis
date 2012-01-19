$: << "../lib/"
require 'symbiosis/firewall/template'
require 'test/unit'
require 'fileutils'

class TestFirewallTemplate < Test::Unit::TestCase

  include Symbiosis::Firewall

  def setup
    @template_dirs = [ File.join(File.dirname(__FILE__),"rule.d") ]
    Ports.reset
  end

  def teardown
  end

  def test_built_in_named_rule
    r = Template.new("rule.d/accept.incoming")
    r.name = "smtp"
    r.direction = "incoming"

    #
    # This will get boiled down to 2001:ba8:123::/56
    #
    r.address = "2001:ba8:123:0::12/56"

    #
    # This should generate
    #
    results = []
    results << "/sbin/ip6tables -A INPUT -p tcp --dport 25 --src 2001:ba8:123::/56 -j ACCEPT"
    results << "/sbin/ip6tables -A INPUT -p udp --dport 25 --src 2001:ba8:123::/56 -j ACCEPT"

    #
    # TODO this test is rubbish.
    #
    r.to_s.split("\n").each do |s|
      next if s.empty?
      assert(results.include?(s), "Results do not include #{s.inspect}")
    end
  end

  def test_built_in_numbered_rule
    r = Template.new("rule.d/accept.incoming")
    r.name = "1919"
    r.direction = "incoming"
    r.address = "2001:ba8:123:0::12/56"
    puts r.to_s if $VERBOSE
  end
  
  def test_legacy_rule_without_subst
    r = Template.new("rule.d/accept-old.incoming")
    r.name = "accept"
    r.direction = "incoming"
    puts r.to_s if $VERBOSE
  end

  def test_legacy_rule_ipv4
    r = Template.new("rule.d/accept-old.incoming")
    r.name = "accept"
    r.direction = "incoming"
    r.address = "1.2.3.4/30"
    puts r.to_s if $VERBOSE
  end
  
  def test_legacy_rule_ipv6
    r = Template.new("rule.d/accept-old.incoming")
    r.name = "accept"
    r.direction = "incoming"
    r.address = "2001:ba8:123:0::12/56"
    puts r.to_s if $VERBOSE
  end

  def test_new_rule_ipv4
    r = Template.new("rule.d/accept.incoming")
    r.name = "accept"
    r.direction = "incoming"
    r.address = "1.2.3.4/30"
    puts r.to_s if $VERBOSE
  end

  def test_new_rule_ipv6
    r = Template.new("rule.d/accept.incoming")
    r.name = "accept"
    r.direction = "incoming"
    r.address = "2001:ba8:123:0::12/56"
    puts r.to_s if $VERBOSE
  end

  def test_new_rule_all_ipv4
    r = Template.new("rule.d/accept.incoming")
    r.name = "accept"
    r.direction = "incoming"
    puts r.to_s if $VERBOSE
  end

#  def test_new_rule_icmp_echo_reply
#    r = Template.new("icmp-echo-reply")
#    r.template_dirs = @template_dirs
#    puts r.to_s
#  end
#
#  def test_new_rule_icmp6_echo_reply
#    r = Template.new("icmpv6-echo-reply")
#    r.template_dirs = @template_dirs
#    puts r.to_s
#  end
#

end




