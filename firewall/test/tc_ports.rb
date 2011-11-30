$: << "../lib/"
require 'symbiosis/firewall/ports'
require 'test/unit'

class TestPorts < Test::Unit::TestCase
  include Symbiosis

  def setup
  end

  def teardown
  end

  def test_parsing
    ports = nil
    assert_nothing_raised do
      ports = Firewall::Ports.new(File.dirname(__FILE__)+"/services")
    end

    assert_equal(4, ports.services.length)
    assert_equal(25, ports.services['mail'])
    assert_equal(25, ports.services['inboundmail'])
    assert_equal(25, ports.services['smtp'])
    assert_equal(7, ports.services['echo'])
    assert_nil(ports.services['blah'])
  end

end


