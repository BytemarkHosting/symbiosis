$:.unshift "../lib"

require 'test/unit'
require 'symbiosis/monitor/state_db'
require 'pp'

class TestStateDb < Test::Unit::TestCase


  def setup
    @statedb_fn = "#{__FILE__}.#{$$}.db"
    @statedb = Symbiosis::Monitor::StateDB.new(@statedb_fn)
  end

  def teardown
    File.unlink(@statedb_fn) if File.exist?(@statedb_fn)
  end

  def test_create_table
    #
    # The table should be created when the state db is initialized.
    #
    assert(@statedb.table_exists?)

    #
    # Don't create the table twice.
    #
    assert_nothing_raised{ @statedb.create_table }
  end

  def test_record
    test = "test_record"
    output = "ok\nok\nok"
    exitstatus = 12
    at = Time.now-100

    assert_nothing_raised{ @statedb.record(test, exitstatus, output, at) }

    results = @statedb.dbh.execute("SELECT * FROM states WHERE test = ? ORDER BY timestamp DESC",test)

    result = results.first
    assert_equal(1, results.length)
    assert_equal(test, result['test'])
    assert_equal(at.to_i, result['timestamp'])
    assert_equal(exitstatus, result['exitstatus'])
    assert_equal(output, result['output'])

    #
    # New result, a few seconds later.
    #
    at += 9
    assert_nothing_raised{ @statedb.record(test, exitstatus, output, at) }
    
    results = @statedb.dbh.execute("SELECT * FROM states WHERE test = ? ORDER BY timestamp DESC",test)
    #
    # Make sure we still only have one result.
    #
    assert_equal(1, results.length)
    result = results.first
    assert_equal(test, result['test'])
    assert_equal(at.to_i, result['timestamp'])
    assert_equal(exitstatus, result['exitstatus'])
    assert_equal(output, result['output'])
    
    #
    # Record a different exit status.
    #
    at += 9
    exitstatus += 1
    assert_nothing_raised{ @statedb.record(test, exitstatus, output, at) }
    
    results = @statedb.dbh.execute("SELECT * FROM states WHERE test = ? ORDER BY timestamp DESC",test)
    #
    # Make sure we now have two results
    #
    assert_equal(2, results.length)
    result = results.first
    assert_equal(test, result['test'])
    assert_equal(at.to_i, result['timestamp'])
    assert_equal(exitstatus, result['exitstatus'])
    assert_equal(output, result['output'])

    #
    # Now go back to the old exit status.
    #
    at += 9
    exitstatus -= 1
    assert_nothing_raised{ @statedb.record(test, exitstatus, output, at) }

    results = @statedb.dbh.execute("SELECT * FROM states WHERE test = ? ORDER BY timestamp DESC",test)
    #
    # Make sure we now have three results.
    #
    assert_equal(3, results.length)
    result = results.first
    assert_equal(test, result['test'])
    assert_equal(at.to_i, result['timestamp'])
    assert_equal(exitstatus, result['exitstatus'])
    assert_equal(output, result['output'])
  end

  def test_last_result
    test = "test_last_result"
    output = "ok\nok\nok\nblah\nbah"
    exitstatus = 12
    at = Time.now-100

    assert_nothing_raised{ @statedb.record(test, exitstatus, output, at) }

    result = @statedb.last_result_for(test)
    assert_kind_of(Hash, result)
    assert_equal(at.to_i, result['timestamp'])
    assert_equal(exitstatus, result['exitstatus'])
    assert_equal(output, result['output'])
  end

  def test_last_success
    test = "test_last_success"
    output = "ok\nok\nok\nblah\nbah"
    exitstatus = 0
    at = Time.now-100

    assert_nothing_raised{ @statedb.record(test, exitstatus, output, at) }

    result = @statedb.last_success(test)
    assert_kind_of(Hash, result)
    assert_equal(at.to_i, result['timestamp'])
    assert_equal(exitstatus, result['exitstatus'])
    assert_equal(output, result['output'])

    #
    # Record a failure
    #
    assert_nothing_raised{ @statedb.record(test, 1, "FAIL!", at+10) }

    result = @statedb.last_success(test)
    assert_kind_of(Hash, result)
    assert_equal(at.to_i, result['timestamp'])
    assert_equal(exitstatus, result['exitstatus'])
    assert_equal(output, result['output'])

    #
    # Record another success
    #
    assert_nothing_raised{ @statedb.record(test, exitstatus, output, at+20) }

    result = @statedb.last_success(test)
    assert_kind_of(Hash, result)
    assert_equal(at.to_i+20, result['timestamp'])
    assert_equal(exitstatus, result['exitstatus'])
    assert_equal(output, result['output'])

    #
    # Record a success for a different test.
    #
    assert_nothing_raised{ @statedb.record("test_something_else", exitstatus, output, at+30) }

    result = @statedb.last_success(test)
    assert_kind_of(Hash, result)
    assert_equal(at.to_i+20, result['timestamp'])
    assert_equal(exitstatus, result['exitstatus'])
    assert_equal(output, result['output'])
  end

  def test_clean
    test = "test_last_success"
    output = "ok\nok\nok\nblah\nbah"
    exitstatus = 0
    #
    # 20 days ago.
    #
    at = Time.now-20*86400

    20.times do
      assert_nothing_raised{ @statedb.record(test, exitstatus, output, at) }
      at += 86400
      exitstatus += 1
    end

    results = @statedb.all_results_for(test)
    assert_equal(20, results.length)

    @statedb.clean(10, at)

    results = @statedb.all_results_for(test)
    assert_equal(10, results.length)

  end

  # TODO more tests..

end

