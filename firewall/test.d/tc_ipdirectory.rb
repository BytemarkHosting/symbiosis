
$: << "../lib/"
require 'symbiosis/firewall/directory'
require 'test/unit'
require 'pp'
require 'tmpdir'

class TestFirewallIPDirectory < Test::Unit::TestCase

  include Symbiosis::Firewall

  def setup
    #
    # Use a temporary directory
    #
    @prefix = Dir.mktmpdir("firewall")
  end

  def teardown
    #
    # Remove the @prefix directory
    #
    FileUtils.remove_entry_secure @prefix
  end

  def test_basics
    file_contents = {
      "1.2.3.1" => "all",
      "1.2.3.2" => "    ",
      "1.2.3.3" => nil,
      "1.2.3.5" => "465",
      "1.2.3.6" => "smtp",
      "1.2.3.7" => "465\n587",
      "1.2.3.8" => "# This is a comment\n465\n# 587\n993",
      "1.2.3.9.auto" => "    ",
      "2001:41c8::1" => nil,
      "2001:41c8:1::1|29" => nil,
      "www.example.com" => nil
    }

    expected = {
      nil => %w(1.2.3.1 1.2.3.2 1.2.3.3 1.2.3.9 2001:41c8::1 2001:41c8:1::1/29 www.example.com),
      "smtp" => %w(1.2.3.6),
      "465" => %w(1.2.3.5 1.2.3.7 1.2.3.8),
      "587" => %w(1.2.3.7),
      "993" => %w(1.2.3.8)
    }


    file_contents.each do |fn, contents|
      File.open(File.join(@prefix, fn), "w+") do |fh|
        fh.puts contents unless contents.nil?
      end
    end

    results = nil

    assert_nothing_raised("Failed to read IPDirectory rules") do
      Template.directories = ["rule.d"]
      list = IPListDirectory.new(@prefix,"incoming","blacklist" )
      results = list.read
    end

    assert_kind_of(Array, results)
    assert_equal(expected.length, results.length)

    expected.each do |port, hosts|
      #
      # Ugh, setting up a template is horrid.
      # 
      e_template = Template.new("rule.d")
      e_template.port = port unless port.nil?

      result = results.select{|r| r[0].port == e_template.port}

      assert_kind_of(Array, result)
      assert_equal(1, result.length)

      r_hosts = result[0][1]
      assert_kind_of(Array, r_hosts)

      hosts.each do |host|
        assert(r_hosts.include?(host), "Host #{host} not found in IPListDirectory rules")
      end
    end
  end
  
end


