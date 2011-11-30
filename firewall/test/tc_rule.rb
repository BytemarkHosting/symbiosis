$: << "../lib/"
$: << "../ext/"
require 'symbiosis/firewall/rule'
require 'test/unit'
require 'fileutils'

class TestFirewallRule < Test::Unit::TestCase

  include Symbiosis

  def setup
    @template_dir = File.join(File.dirname(__FILE__),"rule.d")
  end

  def teardown
  end

  def test_built_in_named_rule
    r = Firewall::Rule.new("smtp")
    r.template_dir = @template_dir
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
    r = Firewall::Rule.new("1919")
    r.template_dir = @template_dir
    r.address = "2001:ba8:123:0::12/56"
    r.incoming
    puts r.to_s
  end
  
  def test_legacy_rule_without_subst
    r = Firewall::Rule.new("allow-old")
    r.template_dir = @template_dir
    puts r.to_s
  end

  def test_legacy_rule_ipv4
    r = Firewall::Rule.new("allow-old")
    r.template_dir = @template_dir
    r.address = "1.2.3.4/30"
    puts r.to_s
  end
  
  def test_legacy_rule_ipv6
    r = Firewall::Rule.new("allow-old")
    r.template_dir = @template_dir
    r.address = "2001:ba8:123:0::12/56"
    puts r.to_s
  end

  def test_new_rule_ipv4
    r = Firewall::Rule.new("allow")
    r.template_dir = @template_dir
    r.address = "1.2.3.4/30"
    puts r.to_s
  end

  def test_new_rule_ipv6
    r = Firewall::Rule.new("allow")
    r.template_dir = @template_dir
    r.address = "2001:ba8:123:0::12/56"
    puts r.to_s
  end

  def test_new_rule_all_ipv
    r = Firewall::Rule.new("allow")
    r.template_dir = @template_dir
    puts r.to_s
  end

end



