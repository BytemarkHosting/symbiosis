$: << "../lib/"
$: << "../ext/"
require 'symbiosis/utmp'
require 'test/unit'
require 'fileutils'

class TestUtmp < Test::Unit::TestCase

  def setup
    @wtmp = "wtmp-test"
    system("gcc create-wtmp-test.c -o create-wtmp-test")
    FileUtils.touch(@wtmp)
    system("./create-wtmp-test")
  end

  def teardown
    FileUtils.rm_f(@wtmp)
    FileUtils.rm_f("create-wtmp-test")
  end

  def test_read
    wtmp = nil
    assert(File.exists?(@wtmp))
    assert_nothing_raised {
      wtmp = Symbiosis::Utmp.read(@wtmp);
    }

    assert_equal(3, wtmp.length)

    [
      [7, 1001, "pts/10", "alice", Time.at(1278054000.135790), "office.my-brilliant-site.com", IPAddr.new("1.2.3.4")],
      [7, 2001, "pts/11", "bob", Time.at(1278055800.654321), "shop.my-brilliant-site.com", IPAddr.new("2001:ba8:dead:beef:cafe::1")],
      [7, 3001, "pts/12", "charlie", Time.at(1278057600.024680), "garage.my-brilliant-site.com", IPAddr.new("192.0.2.128")]
    ].zip(wtmp).each do |b|
      type, pid, line, user, time, host, ip, entry = b.flatten
      assert_equal(type, entry["type"])
      assert_equal(pid,  entry["pid"])
      assert_equal(line, entry["line"])
      assert_equal(user, entry["user"])
      assert_equal(time, entry["time"])
      assert_equal(host, entry["host"])
      assert_equal(ip,   entry["ip"])
    end
  end
end
