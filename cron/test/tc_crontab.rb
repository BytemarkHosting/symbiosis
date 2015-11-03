#!/usr/bin/ruby
#

    require 'pp'
require 'test/unit'
require 'symbiosis/crontab'

class TestCrontab < Test::Unit::TestCase

  def setup
    @crontab = nil
  end

  def teardown
  end

  def test_documentation_example

    assert_nothing_raised do
      # Note this crontab has no newline at the end.  Specially for Mr Howells.
      @crontab = Symbiosis::Crontab.new " 
#
# Send any output to Bob
#
MAILTO=bob@my-brilliant-site.com

#
# run at 18:40 every day
#
40 18 * * *       echo Hello Dave.

#
# run at 9am every Monday - Friday
#
0   9 * * mon-fri wget http://www.my-brilliant-site.com/cron.php

#
# Run once a month
#
@monthly          /usr/local/bin/monthly-job.sh

#
# run every minute
#
* * * * * php --some-argument-or-other cronjob.php
"
    end

    assert_equal("bob@my-brilliant-site.com",@crontab.environment["MAILTO"])
    
    # Test first entry -- run at 18:40 every day
    #
    record = @crontab.records[0]
    assert_equal([40], record.min)
    assert_equal([18], record.hour)
    assert_equal((1..31).to_a, record.mday)
    assert_equal((1..12).to_a, record.mon)
    assert_equal((0..6).to_a, record.wday)
    assert_equal("echo Hello Dave.", record.command)

    # Next entry -- run at 9am every Monday - Friday
    #
    record = @crontab.records[1]
    assert_equal([0], record.min)
    assert_equal([9], record.hour)
    assert_equal((1..31).to_a, record.mday)
    assert_equal((1..12).to_a, record.mon)
    assert_equal((1..5).to_a, record.wday)
    assert_equal("wget http://www.my-brilliant-site.com/cron.php", record.command)

    # Next entry -- Run once a month
    #
    record = @crontab.records[2]
    assert_equal([0], record.min)
    assert_equal([0], record.hour)
    assert_equal([1], record.mday)
    assert_equal((1..12).to_a, record.mon)
    assert_equal((0..6).to_a, record.wday)
    assert_equal("/usr/local/bin/monthly-job.sh", record.command)
    
    # Next entry -- Run every minute
    #
    record = @crontab.records[3]
    assert_equal((0..59).to_a, record.min)
    assert_equal((0..23).to_a, record.hour)
    assert_equal((1..31).to_a, record.mday)
    assert_equal((1..12).to_a, record.mon)
    assert_equal((0..6).to_a, record.wday)
    assert_equal("php --some-argument-or-other cronjob.php", record.command)
  end

end

class TestCrontabRecord < Test::Unit::TestCase

  def test_manpage_eg1
    # run five minutes after midnight, every day
    crontab_record = nil
    assert_nothing_raised {
      crontab_record = Symbiosis::CrontabRecord.parse("5 0 * * *       $HOME/bin/daily.job >> $HOME/tmp/out 2>&1")
    }
    assert_equal([5], crontab_record.min)
    assert_equal([0], crontab_record.hour)
    assert_equal((1..31).to_a, crontab_record.mday)
    assert_equal((1..12).to_a, crontab_record.mon)
    assert_equal((0..6).to_a, crontab_record.wday)
    assert_equal("$HOME/bin/daily.job >> $HOME/tmp/out 2>&1", crontab_record.command)
  end

  def test_manpage_eg2
    # run at 2:15pm on the first of every month
    crontab_record = nil
    assert_nothing_raised {
      crontab_record = Symbiosis::CrontabRecord.parse("15 14 1 * *     $HOME/bin/monthly")
    }

    assert_equal([15], crontab_record.min)
    assert_equal([14], crontab_record.hour)
    assert_equal([1], crontab_record.mday)
    assert_equal((1..12).to_a, crontab_record.mon)
    assert_equal((0..6).to_a, crontab_record.wday)
    assert_equal("$HOME/bin/monthly", crontab_record.command)
  end

  def test_manpage_eg3
    # run at 10 pm on weekdays, annoy Joe
    crontab_record = nil
    assert_nothing_raised {
      crontab_record = Symbiosis::CrontabRecord.parse("0 22 * * 1-5    mail -s \"It's 10pm\" joe%Joe,%%Where are your kids?%")
    }

    assert_equal([0], crontab_record.min)
    assert_equal([22], crontab_record.hour)
    assert_equal((1..31).to_a, crontab_record.mday)
    assert_equal((1..12).to_a, crontab_record.mon)
    assert_equal((1..5).to_a, crontab_record.wday)
    assert_equal("mail -s \"It's 10pm\" joe%Joe,%%Where are your kids?%", crontab_record.command)
    
  end

  def test_manpage_eg4 
#       23 0-23/2 * * * echo "run 23 minutes after midn, 2am, 4am ..., everyday"
    crontab_record = nil
    assert_nothing_raised {
      crontab_record = Symbiosis::CrontabRecord.parse('23 0-23/2 * * * echo "run 23 minutes after midn, 2am, 4am ..., everyday"')
    }
    assert_equal([23], crontab_record.min)
    assert_equal([0,2,4,6,8,10,12,14,16,18,20,22], crontab_record.hour)
    assert_equal((1..31).to_a, crontab_record.mday)
    assert_equal((1..12).to_a, crontab_record.mon)
    assert_equal((0..6).to_a, crontab_record.wday)
    assert_equal('echo "run 23 minutes after midn, 2am, 4am ..., everyday"', crontab_record.command)
  end

  def test_manpage_eg5
    crontab_record = nil
    assert_nothing_raised {
      crontab_record = Symbiosis::CrontabRecord.parse('5 4 * * sun     echo "run at 5 after 4 every sunday"')
    }
    assert_equal([5], crontab_record.min)
    assert_equal([4], crontab_record.hour)
    assert_equal((1..31).to_a, crontab_record.mday)
    assert_equal((1..12).to_a, crontab_record.mon)
    assert_equal([0], crontab_record.wday)
    assert_equal('echo "run at 5 after 4 every sunday"', crontab_record.command)
  end

  def test_hourly
    crontab_record = nil
    assert_nothing_raised {
      crontab_record = Symbiosis::CrontabRecord.parse("@hourly do my stuff")
    }
    assert_equal([0], crontab_record.min)
    assert_equal((0..23).to_a, crontab_record.hour)
    assert_equal((1..31).to_a, crontab_record.mday)
    assert_equal((1..12).to_a, crontab_record.mon)
    assert_equal((0..6).to_a, crontab_record.wday)
    assert_equal("do my stuff", crontab_record.command)
  end
  
  def test_daily_midnight
    crontab_record = nil
    %w(daily midnight).each do |d|
      assert_nothing_raised {
        crontab_record = Symbiosis::CrontabRecord.parse("@#{d} do my stuff")
      }
      assert_equal([0], crontab_record.min)
      assert_equal([0], crontab_record.hour)
      assert_equal((1..31).to_a, crontab_record.mday)
      assert_equal((1..12).to_a, crontab_record.mon)
      assert_equal((0..6).to_a, crontab_record.wday)
      assert_equal("do my stuff", crontab_record.command)
    end
  end


  def test_weekly
    crontab_record = Symbiosis::CrontabRecord.parse("@weekly do my stuff")
    assert_equal([0], crontab_record.min)
    assert_equal([0], crontab_record.hour)
    assert_equal((1..31).to_a, crontab_record.mday)
    assert_equal((1..12).to_a, crontab_record.mon)
    assert_equal([0], crontab_record.wday)
    assert_equal("do my stuff", crontab_record.command)
  end

  
  def test_monthly
    crontab_record = Symbiosis::CrontabRecord.parse("@monthly do my stuff")
    assert_equal([0], crontab_record.min)
    assert_equal([0], crontab_record.hour)
    assert_equal([1], crontab_record.mday)
    assert_equal((1..12).to_a, crontab_record.mon)
    assert_equal((0..6).to_a, crontab_record.wday)
    assert_equal("do my stuff", crontab_record.command)
  end

  def test_annually
    %w(annually yearly).each do |d|
      crontab_record = Symbiosis::CrontabRecord.parse("@#{d} do my stuff")
      assert_equal([0], crontab_record.min)
      assert_equal([0], crontab_record.hour)
      assert_equal([1], crontab_record.mday)
      assert_equal([1], crontab_record.mon)
      assert_equal((0..6).to_a, crontab_record.wday)
      assert_equal("do my stuff", crontab_record.command)
    end
  end

  def test_wday_names
    names = %w(sun mon tue wed thu fri sat sun)
    values = [0,1,2,3,4,5,6,0]
    names.each_with_index do |wday,ind|
      crontab_record = Symbiosis::CrontabRecord.parse("* * * * #{wday} do my bidding")
      assert_equal([values[ind]], crontab_record.wday)
    end

    crontab_record = Symbiosis::CrontabRecord.parse("* * * * mon-fri do my bidding")
    assert_equal((1..5).to_a, crontab_record.wday)

    crontab_record = Symbiosis::CrontabRecord.parse("* * * * sat-sun do my bidding")
    assert_equal([0,6], crontab_record.wday)

    # Stupid people not reading instructions.
    crontab_record = Symbiosis::CrontabRecord.parse("* * * * sUnDaY-SATURDAY do my bidding")
    assert_equal((0..6).to_a, crontab_record.wday)
  end

  def test_mon_names
    names = %w(jan feb mar apr may jun jul aug sep oct nov dec)
    values =   [1, 2,  3,  4,  5,  6,  7,  8,  9,  10, 11, 12]
    names.each_with_index do |mon,ind|
      crontab_record = Symbiosis::CrontabRecord.parse("* * * #{mon} * do my bidding")
      assert_equal([values[ind]], crontab_record.mon)
    end

    # a range of names
    crontab_record = Symbiosis::CrontabRecord.parse("* * * jan,mar,jun-sep * do my bidding")
    assert_equal([1,3,6,7,8,9], crontab_record.mon)

    # test long names
    crontab_record = Symbiosis::CrontabRecord.parse("* * * january,february,march,april,may,june,july,august,september,october,november,december * do my bidding")
    assert_equal((1..12).to_a, crontab_record.mon)
   
    # make sure that the regexp starts from the beginning of a word.
    crontab_record = Symbiosis::CrontabRecord.parse("* * * janjan,marfeb * do my bidding")
    assert_equal([1,3], crontab_record.mon)

    # Test year boundary parsing
    crontab_record = Symbiosis::CrontabRecord.parse("* * * nov-feb * do my bidding")
    assert_equal([1,2,11,12], crontab_record.mon)
  end

  def test_silly_combinations

    #    October 2011      
    # Su Mo Tu We Th Fr Sa  
    #                    1  
    #  2  3  4  5  6  7  8  
    #  9 10 11 12 13 14 15  
    # 16 17 18 19 20 21 22  
    # 23 24 25 26 27 28 29  
    # 30 31
    #
    today = Time.new(2011,9,30,0,0,0)

    # This should be any Monday in October
    crontab_record = Symbiosis::CrontabRecord.parse("11 11  *  10 1 echo \"monday in october\"")
    assert_equal_date( Time.new(2011,10,3,11,11,0), crontab_record.next_due(today) )

    # This should run on the next 10th October, and any Sunday in October
    crontab_record = Symbiosis::CrontabRecord.parse("10 10  10  10 0 echo \"Sunday or 10th October\"")

    x = crontab_record.next_due(today)
    assert_equal_date( Time.new(2011,10,2,10,10,0), x )

    x = crontab_record.next_due(x + 120) 
    assert_equal_date( Time.new(2011,10,9,10,10,0), x )

    x = crontab_record.next_due(x + 120)
    assert_equal_date( Time.new(2011,10,10,10,10,0), x )


    # This should be run at midnight on 31st Sept, i.e. never.
    crontab_record = Symbiosis::CrontabRecord.parse("0  0   31 9  * echo \"impossible?\"")
    assert_nil(crontab_record.next_due(today))
  end

  def test_single_hyphen_arguments
    crontab_record = Symbiosis::CrontabRecord.parse("@hourly wget -O - -q -t 1 http://www.example.com/cron.php")
    assert_equal("wget -O - -q -t 1 http://www.example.com/cron.php",crontab_record.command)
  end

  #
  # There was a typo which occured when calculating the next due date during
  # crontab tests.
  #
  def test_ticket_569757
    crontab_record = Symbiosis::CrontabRecord.parse("30 7 * * 5 /do/some/stuff")
    now = Time.new(2014,1,15,17,0,0)

    assert_equal_date(Time.new(2014,1,17,7,30,0), crontab_record.next_due(now))
  end

  #
  # This checks the date, to the nearest minute.
  #
  def assert_equal_date(expected, actual)
    assert_kind_of(Time, expected)
    assert_kind_of(Time, actual)
    %w(year mon day hour min).each do |m|
      assert_equal(expected.__send__(m), actual.__send__(m), "#{m} should be #{expected.__send__(m)} in #{actual.to_s}")
    end 
  end

  def test_return_sensible_error
    today = Time.new(2011,10,1,0,0,0)
    assert_raise(Symbiosis::CrontabFormatError) do
      # This is missing a field.
      Symbiosis::CrontabRecord.parse("*/5 * * * /usr/bin/php /srv/domain.co.uk/public/htdocs/cron.php")
    end
  end


end
