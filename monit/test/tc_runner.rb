$:.unshift "../lib"

require 'test/unit'
require 'symbiosis/monitor/runner'
require 'log4r'
require 'time'

class TestRunner < Test::Unit::TestCase


  def setup
    @statedb_fn = "#{__FILE__}.#{$$}-#{rand(1000)}.db"
    @monit_d = File.join(File.dirname(__FILE__), "monit.d")
    @template_d = File.join(File.dirname(__FILE__), "../templates")
    @log = Log4r::Logger.new("Symbiosis::Monitor")
    @log.add Log4r::Outputter.stdout()
    #
    # Set up the flip-flop test to fail initially
    #
    @symlinks = [
      ["fail", "success"],
      ["tempfail", "success"],
      ["usagefail", "success"],
      ["flip-flop", "fail"],
      ["temp-flip-flop", "tempfail"]
    ]
    @symlinks.each{|s,r| do_symlink(s,r)}
  end

  def teardown
    File.unlink(@statedb_fn) if File.exists?(@statedb_fn)
    @symlinks.each{|s,r| un_symlink(s)}
  end

  def do_symlink(script, result)
    s = File.join(@monit_d, script)
    File.unlink(s) if File.symlink?(s)
    raise "Awooga! File in the way!" if File.exists?(s)
    File.symlink(result,s)
  end

  def un_symlink(script)
    s = File.join(@monit_d, script)
    File.unlink(s) if File.symlink?(s)
  end

  def test_initialize
    runner = nil
    assert_nothing_raised { runner = Symbiosis::Monitor::Runner.new(@monit_d, @statedb_fn, @template_d) }
    assert_equal(@template_d, runner.template_dir)
  end

  def test_tests
    runner = nil
    assert_nothing_raised { runner = Symbiosis::Monitor::Runner.new(@monit_d, @statedb_fn, @template_d) }

    # There are two tests in our monit directory.
    n_tests = Dir.glob("monit.d/*").length

    assert_kind_of(Array, runner.tests)
    assert_equal(n_tests, runner.tests.length)
    assert(runner.tests.all?{|t| t.kind_of?(Symbiosis::Monitor::Test)})
  end

  def test_logger
    runner = nil
    assert_nothing_raised { runner = Symbiosis::Monitor::Runner.new(@monit_d, @statedb_fn, @template_d) }
    assert_kind_of(Log4r::Logger, runner.logger)
    pp runner.logger
  end

  def test_dpkg_running?
    # TODO -- this needs root permissions
  end

  def test_state_db
    runner = nil
    assert_nothing_raised { runner = Symbiosis::Monitor::Runner.new(@monit_d, @statedb_fn, @template_d) }
    assert_kind_of(Symbiosis::Monitor::StateDB, runner.state_db)
  end

  def test_hostname
    my_hostname = Socket.gethostname
    runner = nil
    assert_nothing_raised { runner = Symbiosis::Monitor::Runner.new(@monit_d, @statedb_fn, @template_d) }
    assert_equal(my_hostname, runner.hostname)
  end

  def test_go
    runner = nil
    assert_nothing_raised { runner = Symbiosis::Monitor::Runner.new(@monit_d, @statedb_fn, @template_d) }
    runner.send_mail = false
    assert(runner.tests.all?{|t| t.timestamp.nil?}, "Not all the tests have nil timestamps" )
    assert_nothing_raised{ runner.go }
    assert( runner.tests.all?{|t| !t.timestamp.nil?}, "Not all the tests were run" )
  end

  def test_test_selections
    runner = nil
    assert_nothing_raised { runner = Symbiosis::Monitor::Runner.new(@monit_d, @statedb_fn, @template_d) }
    assert_nothing_raised{ runner.go }
    assert_equal(4, runner.failed_tests.length, "Wrong number of failed tests")
    assert_equal(2, runner.successful_tests.length, "Wrong number of successful tests")
    assert_equal(1, runner.usage_fail_tests.length, "Wrong number of usage fail tests")
    assert_equal(2, runner.retried_tests.length, "Wrong number of retried tests")
  end

  def test_report
    runner = nil
    assert_nothing_raised { runner = Symbiosis::Monitor::Runner.new(@monit_d, @statedb_fn, @template_d) }
    assert_nothing_raised{ runner.go }
    assert_nothing_raised{ runner.report("default") }
    assert_nothing_raised{ runner.report("brief") }
  end

  def test_should_notify
    runner = nil
    assert_nothing_raised { runner = Symbiosis::Monitor::Runner.new(@monit_d, @statedb_fn, @template_d) }
  
    # With the flip-flop script in place, it should notify every time.  It
    # always starts with a "fail".
    flip_flop_fail = true
    3.times do
      assert_nothing_raised{ runner.reset}
      assert_nothing_raised{ runner.go }
      # The number of failed tests will oscillate between three and four, depending on the flip-flop test.
      assert_equal(3 + (flip_flop_fail ? 1 : 0), runner.failed_tests.length, "Wrong number of failed tests")
      assert(runner.should_notify?, "Runner didn't notify when it should have done.")
      #
      # Flop the flip-flop to what it wasn't..!
      #
      flip_flop_fail = !flip_flop_fail
    end
    #
    # Now remove the flip-flop script.  This should cause notifications to stop
    #
    un_symlink("flip-flop")
    3.times do
      assert_nothing_raised{ runner.reset}
      assert_nothing_raised{ runner.go }
      assert_equal(3, runner.failed_tests.length, "Wrong number of failed tests")
      assert(!runner.should_notify?, "Runner was going to notify when it shouldn't have done")
    end

  end

end

