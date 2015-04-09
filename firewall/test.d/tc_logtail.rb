$: << "../lib/"
require 'symbiosis/firewall/logtail'
require 'test/unit'
require 'pp'

class TestLogtail < Test::Unit::TestCase

  include Symbiosis::Firewall

  def setup
    @db = "test_logtail.db"
  end

  def teardown
   File.unlink(@db) if File.exist?(@db)
  end

  def test_me
    fn = "log/syslog"
    (1..5).each do |f|
      File.symlink("#{File.basename(fn)}.#{f}",fn)
      lt = Logtail.new("log/syslog",@db)
      assert_equal(10, lt.readlines.length, f)
      File.unlink(fn)
    end
    
    (6..10).each do |f|
      File.symlink("#{File.basename(fn)}.#{f}",fn)
      lt = Logtail.new("log/syslog",@db)
      assert_equal(10, lt.readlines.length, f)
      File.unlink(fn)
    end

  ensure
    File.unlink(fn) if File.exist?(fn)
  end
  
end





