# symbiosis/crontab.rb
#
# Based on http://www.notwork.org/~gotoken/ruby/p/crontab/crontab/crontab.rb
# by Kentaro Goto <gotoken@gmail.com>.
#
# Modifications were made by Patrick J Cherry <patrick@bytemark.co.uk> for the
# Bytemark Symbiosis system
#
# HISTORY 
# 
#  2010-06-17: Reworked for Symbiosis <patrick@bytemark.co.uk>
#  2001-01-04: (BUG) camma and slash were misinterpreted <gotoken#notwork.org>
#  2000-12-31: replaced Array#filter with collect! <zn#mbf.nifty.com>
#  2000-07-06: (bug) Crontab#run throws block <gotoken#notwork.org>
#  2000-07-03: (bug) open->File::open <gotoken#notwork.org>
#  2000-04-07: Error is subclass of StandardError <matz#netlab.co.jp>
#  2000-04-06: Fixed bugs. <c.hintze#gmx.net>
#  2000-04-06: Started. <gotoken#notwork.org>
#
# COPYRIGHT
#
# This code is released under the same terms as Ruby itself.  See LICENCE for
# more details.  
#
# (c) 2000-1 Kentaro Goto
# (c) 2010-2012 Bytemark Computer Consulting Ltd
#

require 'stringio'
require 'net/smtp'
require 'date'
require 'time'

#
# Additional methods for DateTime
#
class DateTime

  #
  # Return a string of self in the standard "YYYY-MM-DD hh:mm" format.
  #
  def iso8601
    "%04i-%02i-%02i %02i:%02i" % [ year, month, day, hour, min ]
  end

  #
  # Convert self into a Time.
  #
  def to_time
    Time.local(year, month, day, hour, min, sec)
  end
end

module Symbiosis

  #
  # A class representing a Crontab.
  # 
  class Crontab
    
    # 
    # The array of crontab records
    #
    attr_reader :records

    #
    # The name of the file originally read or "string input" if no file was
    # read
    #
    attr_reader :filename
    
    #
    # The original string input to parse.
    #
    attr_reader :crontab

    #
    # environment is a hash containing environment variables set in the crontab
    #
    attr_reader :environment

    #
    # This takes an argument of a crontab in a string, or a filename.  If a
    # filename is given, it will be read.  Otherwise the string will be parsed. 
    #
    def initialize(string_or_filename = "")
      # Must be a string!
      raise ArgumentError unless string_or_filename.is_a?(String)

      @records     = []
      @environment = {}
      if File.exist?(string_or_filename)
        @filename = string_or_filename
        @crontab = File.open(string_or_filename){|fh| fh.read} 
      else
        @filename = "string input"
        @crontab = string_or_filename
      end
      @mail_output = true
      @mail_command = "/usr/lib/sendmail -t"

      parse(@crontab)
    end

    # 
    # An iterator for each record.
    #
    def each(&block)
      @records.each(&block)
    end

    #
    # This sets the flag to mail output
    #
    def mail_output=(n)
      raise ArgumentError unless n.is_a?(TrueClass) or n.is_a?(FalseClass)
      @mail_output = n
    end

    #
    # This prints the cron environment, and the date/time when each job will
    # next run.
    #
    def test(t = Time.now)
      cron_env = @environment.merge(ENV){|k,o,n| o}
      puts "Environment\n"+"-"*72
      %w(HOME LOGNAME PATH MAILTO).each do |k|
        puts "#{k} = #{cron_env[k]}"
      end
      puts "="*72+"\n\n"
      puts "Jobs next due -- Local time #{t.iso8601}\n"+"-"*72
      puts ("%-20s" % "Date" ) + "Command"
      puts "-"*72
      @records.each do |record|
        n = record.next_due(t)
        puts ("%-20s" % (n.nil? ? "** NEVER **" : n.iso8601))+record.command
      end
      puts "="*72
    end

    #
    # This runs each crontab record.
    #
    def run
      old_env = {}
      @environment.each do |k,v|
        next unless %w(MAILTO PATH).include?(k)
        old_env[k] = (ENV[k].nil? ? nil : ENV[k])
        ENV[k] = v
      end
      output = [] 

      @records.select{|record| record.ready?}.each do |record|
        this_output = record.run
        if this_output.length > 0
          output << record.command+":\n"
          output += this_output
          output << "\n"
        end
      end

      # restore environment
      old_env.each do |k,v|
        if v.nil?
          ENV.delete(k) 
        else
          ENV[k] = v
        end
      end

      return if output.empty?

      if @environment['MAILTO'] and !@environment['MAILTO'].to_s.empty?
        cron_env = @environment.merge(ENV){|k,o,n| o}
        mail = []
        mail << "To: #{@environment['MAILTO']}"
        mail << "Subject: Cron output for #{@filename}"
        %w(SHELL PATH HOME LOGNAME).each do |k|
          mail << "X-Cron-Env: <#{k}=#{cron_env[k]}>" if ENV.has_key?(k)
        end
        mail << "Date: #{Time.now.rfc2822}"
        mail << ""
        mail << output.join
        if @mail_output
          IO.popen(@mail_command,"w+") do |pipe|
            pipe.write mail.join("\n")
            pipe.close
          end 
        else
          puts mail.join("\n")
        end
      else
        puts output
      end
    end

    #
    # Returns any records that are ready to run now.
    #
    def grep(now = Time.now)
      @records.select{|record| record.ready?(now)}
    end

    private

    def parse(str)
      str.split($/).each{|line|
        line.chomp!

        # Skip if line begins with a hash or is all spaces or empty.
        next if line =~ /\A([\s#].*|\s*)\Z/ 

        # Skip unsupported lines
        if line =~ /^\s*@reboot/
          warn "cronjobs to be invoked at @reboot-time are not supported."
          next
        end

        if line =~ /\A([A-Z]+)\s*=\s*(.*)\Z/
          @environment[$1] = $2
        else
          @records << CrontabRecord.parse(line)
        end
      }
    end

  end

  #
  # This is the exception raised if a CrontabRecord could not be interpreted.
  #
  class CrontabFormatError < StandardError; end

  #
  # This class represents and individual line of a crontab
  #
  class CrontabRecord

    #
    # Weekday names that can be used in records
    #
    WDAY = %w(sun mon tue wed thu fri sat)

    #
    # Month names that can be used in records.
    #
    MON  = %w(jan feb mar apr may jun jul aug sep oct nov dec)

    #
    # Hash of names that correspond to @ shortcuts.
    #
    SHORTCUTS = {
       "(?:year|annual)ly"  => "0 0 1 1 *",
       "monthly"            => "0 0 1 * *",
       "weekly"             => "0 0 * * 0",
       "(?:daily|midnight)" => "0 0 * * *",
       "hourly"             => "0 * * * *"
    }

    #
    # Create a new CrontabRecord using a string.  Raises CrontabFormatError if
    # the string parsing fails.
    #
    def self.parse(str)
      if str =~ /\A(?:@(?:#{SHORTCUTS.keys.join("|")})\s+|(?:\S+\s+){5})(.*)\Z$/

        # pick off the last match
        command = $+

        # replace any shortcuts
        SHORTCUTS.collect{|shortcut, snippet| str.sub!(/\A\s*@#{shortcut}/, snippet)}

        min, hour, mday, mon, wday = str.split(/\s+/).first(5)
       
        # This regexp makes sure we start at a word boundary (\b), and can take
        # names longer than the ones specified. 
        wday = wday.downcase.gsub(/\b(#{WDAY.join("|")})[a-z]*/){
          WDAY.index($1)
        }
 
        # Same as above, but have to add one, as months start at 1 not 0.
        mon = mon.downcase.gsub(/\b(#{MON.join("|")})[a-z]*/){
          MON.index($1)+1
        }

        self.new(min, hour, mday, mon, wday, command)
      else
        raise CrontabFormatError, "Badly formatted line: #{str.inspect}"
      end
    end

    attr_reader :min, :hour, :mday, :mon, :wday, :command

    #
    # Create a new CrontabRecord, setting the minute, hour, month-day, month,
    # week-day and command.  Raises a CrontabFormatError if any of the
    # arguments fail to parse. 
    #
    def initialize(min, hour, mday, mon, wday, command)
      @min  = parse_field(min,  0, 59)
      @hour = parse_field(hour, 0, 23)
      @mday = parse_field(mday, 1, 31)
      @mon  = parse_field(mon,  1, 12)
      @wday = parse_field(wday, 0, 7)

      # normalize weekdays
      @wday = @wday.collect{|w| w == 7 ? 0 : w }.sort.uniq

      #
      # If both mday and wday are restricted, then match on either mday or
      # wday.
      #
      @lazy_mday_wday_match = (@mday != (1..31).to_a and @wday != (0..6).to_a)

      self.command = command
    end

    #
    # Set the command to c.  Accepts a String or Proc.
    #
    def command=(c)
      raise ArgumentError, "Commands must be a String or a Proc" unless c.is_a?(String) or c.is_a?(Proc)
      @command = c
    end

    #
    # Returns true if the record should be run at time set by now.
    #
    def ready?(now = Time.now) 
      now = now.to_time 
      if @lazy_mday_wday_match
        min.include?  now.min  and
        hour.include? now.hour and
        mon.include?  now.mon  and
        ( mday.include? now.mday or
          wday.include? now.wday )
      else
        min.include?  now.min  and
        hour.include? now.hour and
        mon.include?  now.mon  and
        mday.include? now.mday  and
        wday.include? now.wday
      end
    end

    #
    # Determines when the record is next due to be run.  Returns a Time if
    # the time could be determined, or nil if the record is not due to run any
    # time in the 30 years after now.
    #
    def next_due(now = Time.now)
      time      = now.to_time
      orig_time = time

      while !ready?(time)
        # find the next minute that matches
        unless min.include?(time.min)
          ind = (min + [time.min]).sort.index(time.min)

          if min.length == ind
            # Roll on time to the beginning of the next hour
            #
            time += 3600
            time = Time.local(time.year, time.mon, time.day, time.hour, time.min) 
          else
            time = Time.local(time.year, time.mon, time.day, time.hour, min[ind]) 
          end
        end

        # find the next hour that matches
        unless hour.include?(time.hour)
          ind = (hour + [time.hour]).sort.index(time.hour)

          if hour.length == ind
            # Roll on time to the beginning of the next day
            dtime = time.to_date + 1
            time = Time.local(dtime.year, dtime.mon, dtime.day)
          else
            time = Time.local(time.year, time.mon, time.day, hour[ind], time.min, 0) 
          end
        end  
        
        time_a = time_b = nil

        # find the next month or week day that matches
        if (!mday.include?(time.mday) or @lazy_mday_wday_match)
          ind = (mday + [time.mday]).sort.index(time.mday)

          if mday.length == ind
            dtime = time.to_date >> 1
            time_a = Time.local(dtime.year, dtime.mon, dtime.mday) 
          else
            begin
              time_a = Time.local(time.year, time.mon, mday[ind], time.hour, time.min) 
            rescue ArgumentError
              dtime = time.to_date >> 1
              time_a = Time.local(dtime.year, dtime.mon)
            end
          end

          time = time_a unless @lazy_mday_wday_match
        end

        if (!wday.include?(time.wday) or @lazy_mday_wday_match)
          ind = (wday + [time.wday]).sort.index(time.wday)

          if wday.length == ind
            # Roll on time to the beginning of the next week, and add the first day.
            dtime = time.to_date + (7 - time.wday + wday.first)
            time_b = Time.local(dtime.year, dtime.mon, dtime.mday)
          else
            dtime = time.to_date + (wday.first - time.wday) 
            time_b = Time.local(dtime.year, dtime.mon, dtime.mday, time.hour, time.min)
          end

          time = time_b unless @lazy_mday_wday_match
        end

        if @lazy_mday_wday_match and time_a.is_a?(Time) and time_b.is_a?(Time)
          time = (time_a < time_b ? time_a : time_b)
        end

        # The next month that matches
        unless mon.include?(time.mon)
          ind = (mon + [time.mon]).sort.index(time.mon)

          if mon.length == ind
            # Roll on time to the beginning of the next year 
            time = Time.local(time.year + 1)
          else
            begin
              time = Time.local(time.year, mon[ind], time.mday, time.hour, time.min)
            rescue ArgumentError
              dtime = time.to_date >> 1
              time = Time.local(dtime.year, dtime.mon)
            end
          end
        end
        
        # Break if we get 30 years into the future!
        if time.year - orig_time.year > 30
          time = nil
          break
        end
      end

      time
    end


    #
    # Run the command.  Returns an arry of strings as output.
    #
    def run
      # OK to run we're just going to run the command in a pipe.
      #
      ret = IO.popen(@command) { |pipe| pipe.readlines }
      # Check for a duff exit status.
      if !$?.success?
        ret << "Command failed with exit status #{$?.exitstatus}\n"
      end
      ret
    end
    
    private

    def parse_field(str, first, last)
      str.split(",").map do |entry|
        every, f, l = nil

        #
        # Split the field, assuming it looks like "0-9/4". 
        #
        if entry.strip =~ /(\*|\d+)(?:\-(\d+))?(?:\/(\d+))?/
          f,l,every = [$1, $2, $3]
          every = (every ? every.to_i : 1)
          raise CrontabFormatError.new "Bad specifier #{every.inspect} in #{str.inspect}" if every < 1
        else
          raise CrontabFormatError.new "Bad entry #{entry.inspect} in field #{str.inspect}"
        end

        range = if f == "*"
          first..last
        else
          l = f if l.nil?

          # make sure we have integers
          f,l = [f,l].collect do |n|

            if n.is_a?(String)
              # Make sure we're going to get a sensible answer
              raise CrontabFormatError.new "Bad field #{n.inspect} in #{str}" unless n =~ /^\d+$/
              n = n.to_i
            end

            # Make sure we've got an integer now
            raise CrontabFormatError.new "Bad field #{n.inspect} in #{str}" unless n.is_a?(Integer)

            # make sure everything is within ranges 
            raise CrontabFormatError.new "out of range (#{n} for #{first}..#{last})" unless (first..last).include?(n)

            n
          end

          # deal with out-of-order ranges
          if l < f
            (f..last).to_a + (first..l).to_a
          else
            f..l
          end
        end

        range.to_a.find_all{|i| (i - first) % every == 0}

      end.flatten.sort.uniq
    end

  end

end
