#!/usr/bin/ruby

require 'test/unit'
require 'symbiosis/crontab'
require 'pp'

class TestCrontabRecord < Test::Unit::TestCase

  def setup
    @crontab_record = nil
  end

  def teardown
  end

  def test_manpage_eg1
    # run five minutes after midnight, every day
    assert_nothing_raised {
      @crontab_record = Symbiosis::CrontabRecord.parse("5 0 * * *       $HOME/bin/daily.job >> $HOME/tmp/out 2>&1")
    }
    assert_equal([5], @crontab_record.min)
    assert_equal([0], @crontab_record.hour)
    assert_equal((1..31).to_a, @crontab_record.mday)
    assert_equal((1..12).to_a, @crontab_record.mon)
    assert_equal((0..6).to_a, @crontab_record.wday)
    assert_equal("$HOME/bin/daily.job >> $HOME/tmp/out 2>&1", @crontab_record.command)
  end

  def test_manpage_eg2
    # run at 2:15pm on the first of every month
    assert_nothing_raised {
      @crontab_record = Symbiosis::CrontabRecord.parse("15 14 1 * *     $HOME/bin/monthly")
    }

    assert_equal([15], @crontab_record.min)
    assert_equal([14], @crontab_record.hour)
    assert_equal([1], @crontab_record.mday)
    assert_equal((1..12).to_a, @crontab_record.mon)
    assert_equal((0..6).to_a, @crontab_record.wday)
    assert_equal("$HOME/bin/monthly", @crontab_record.command)
  end

  def test_manpage_eg3
    # run at 10 pm on weekdays, annoy Joe
    assert_nothing_raised {
      @crontab_record = Symbiosis::CrontabRecord.parse("0 22 * * 1-5    mail -s \"It's 10pm\" joe%Joe,%%Where are your kids?%")
    }

    assert_equal([0], @crontab_record.min)
    assert_equal([22], @crontab_record.hour)
    assert_equal((1..31).to_a, @crontab_record.mday)
    assert_equal((1..12).to_a, @crontab_record.mon)
    assert_equal((1..5).to_a, @crontab_record.wday)
    assert_equal("mail -s \"It's 10pm\" joe%Joe,%%Where are your kids?%", @crontab_record.command)
    
  end

  def test_manpage_eg4 
#       23 0-23/2 * * * echo "run 23 minutes after midn, 2am, 4am ..., everyday"
    assert_nothing_raised {
      @crontab_record = Symbiosis::CrontabRecord.parse('23 0-23/2 * * * echo "run 23 minutes after midn, 2am, 4am ..., everyday"')
    }
    assert_equal([23], @crontab_record.min)
    assert_equal([0,2,4,6,8,10,12,14,16,18,20,22], @crontab_record.hour)
    assert_equal((1..31).to_a, @crontab_record.mday)
    assert_equal((1..12).to_a, @crontab_record.mon)
    assert_equal((0..6).to_a, @crontab_record.wday)
    assert_equal('echo "run 23 minutes after midn, 2am, 4am ..., everyday"', @crontab_record.command)
  end

  def test_manpage_eg5
    assert_nothing_raised {
      @crontab_record = Symbiosis::CrontabRecord.parse('5 4 * * sun     echo "run at 5 after 4 every sunday"')
    }
    assert_equal([5], @crontab_record.min)
    assert_equal([4], @crontab_record.hour)
    assert_equal((1..31).to_a, @crontab_record.mday)
    assert_equal((1..12).to_a, @crontab_record.mon)
    assert_equal([0], @crontab_record.wday)
    assert_equal('echo "run at 5 after 4 every sunday"', @crontab_record.command)
  end

  def test_hourly
    assert_nothing_raised {
      @crontab_record = Symbiosis::CrontabRecord.parse("@hourly do my stuff")
    }
    assert_equal([0], @crontab_record.min)
    assert_equal((0..23).to_a, @crontab_record.hour)
    assert_equal((1..31).to_a, @crontab_record.mday)
    assert_equal((1..12).to_a, @crontab_record.mon)
    assert_equal((0..6).to_a, @crontab_record.wday)
    assert_equal("do my stuff", @crontab_record.command)
  end
  
  def test_daily_midnight
    @crontab_record = nil
    %w(daily midnight).each do |d|
      assert_nothing_raised {
        @crontab_record = Symbiosis::CrontabRecord.parse("@#{d} do my stuff")
      }
      assert_equal([0], @crontab_record.min)
      assert_equal([0], @crontab_record.hour)
      assert_equal((1..31).to_a, @crontab_record.mday)
      assert_equal((1..12).to_a, @crontab_record.mon)
      assert_equal((0..6).to_a, @crontab_record.wday)
      assert_equal("do my stuff", @crontab_record.command)
    end
  end


  def test_weekly
    @crontab_record = Symbiosis::CrontabRecord.parse("@weekly do my stuff")
    assert_equal([0], @crontab_record.min)
    assert_equal([0], @crontab_record.hour)
    assert_equal((1..31).to_a, @crontab_record.mday)
    assert_equal((1..12).to_a, @crontab_record.mon)
    assert_equal([0], @crontab_record.wday)
    assert_equal("do my stuff", @crontab_record.command)
  end

  
  def test_monthly
    @crontab_record = Symbiosis::CrontabRecord.parse("@monthly do my stuff")
    assert_equal([0], @crontab_record.min)
    assert_equal([0], @crontab_record.hour)
    assert_equal([1], @crontab_record.mday)
    assert_equal((1..12).to_a, @crontab_record.mon)
    assert_equal((0..6).to_a, @crontab_record.wday)
    assert_equal("do my stuff", @crontab_record.command)
  end

  def test_monthly
    %w(annually yearly).each do |d|
      @crontab_record = Symbiosis::CrontabRecord.parse("@#{d} do my stuff")
      assert_equal([0], @crontab_record.min)
      assert_equal([0], @crontab_record.hour)
      assert_equal([1], @crontab_record.mday)
      assert_equal([1], @crontab_record.mon)
      assert_equal((0..6).to_a, @crontab_record.wday)
      assert_equal("do my stuff", @crontab_record.command)
    end
  end

end
