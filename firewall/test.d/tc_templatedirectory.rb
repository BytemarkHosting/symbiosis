$: << "../lib/"

require 'symbiosis/firewall/directory'
require 'test/unit'
require 'tmpdir'

class TestFirewallTemplateDirectory < Test::Unit::TestCase

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
      "10-accept" => nil,
      "20-smtp" => " ",
      "30-smtp" => "1.2.3.1",
      "31-smtps" => "1.2.3.2\n1.2.3.3",
      "33-1234" => "1.2.3.4",
      "34-1235" => "1.2.3.5\n# 1.2.3.6\n1.2.3.7",
    }

    expected_results = [
      [nil, [nil]],
      ["smtp", [nil]],
      ["smtp", %w(1.2.3.1)],
      ["smtps", %w(1.2.3.2 1.2.3.3)],
      ["1234", %w(1.2.3.4)],
      ["1235", %w(1.2.3.5 1.2.3.7)]
    ]


    file_contents.each do |fn, contents|
      File.open(File.join(@prefix, fn), "w+") do |fh|
        fh.puts contents unless contents.nil?
      end
    end

    results = nil

    assert_nothing_raised("Failed to read TemplateDirectory rules") do
      Template.directories = ["rule.d"]
      list = TemplateDirectory.new(@prefix,"incoming")
      results = list.read
    end

    assert_kind_of(Array, results)
    assert_equal(expected_results.length, results.length)

    (0...expected_results.length).each do |i|

      port, hosts = expected_results[i]

      e_template = Template.new("rule.d")
      e_template.port = port.to_s

      r_template, r_hosts = results[i]

      assert_equal(e_template.port, r_template.port)

      assert_kind_of(Array, r_hosts)

      hosts.each do |host|
        assert(r_hosts.include?(host), "Host #{host} not found in IPListDirectory rules")
      end
    end
  end
  
end

