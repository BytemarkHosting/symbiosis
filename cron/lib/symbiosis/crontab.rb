#
# Based on http://www.notwork.org/~gotoken/ruby/p/crontab/crontab/crontab.rb
#
# Unsure of copyright.


require 'stringio'
require 'net/smtp'
require 'time'

class Symbiosis

  class Crontab
    
    attr_reader :records, :filename, :crontab

    def initialize(string_or_filename = "")
      @records     = []
      @environment = {}
      if File.exists?(string_or_filename)
        @filename = string_or_filename
        @crontab = File.open(string_or_filename){|fh| fh.read} 
      else
        @filename = "string input"
        @crontab = @string_or_filename
      end
      @mail_output = true

      parse(crontab)
    end

    def each(&block)
      @records.each(&block)
    end

    def mail_output=(n)
      raise ArgumentError unless n.is_a?(TrueClass) or n.is_a?(FalseClass)
      @mail_output = n
    end

    def test
      cron_env = @environment.merge(ENV){|k,o,n| o}
      puts "Environment\n"+"-"*11
      %w(HOME LOGNAME SHELL PATH MAILTO).each do |k|
        puts "#{k} = #{cron_env[k]}"
      end
      puts "\nJobs next due"
      puts "/"+"-"*78+"\\"
      puts "| Date                      | Command"
      puts "+"+"-"*27+"+"+"-"*51
      @records.each do |record|
        puts "| "+record.next_due.iso8601+" | "+record.command
      end
      puts "\\"+"-"*78+"/"
    end

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
          IO.popen("/usr/sbin/exim4 -bm -t","w+") do |pipe|
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

    def grep(time = Time.now)
      @records.select{|record| record.ready?(time)}
    end

    private

    def parse(str)
      str.each{|line|
        line.chomp!

        # Skip if line begins with a hash or is all spaces or empty.
        next if line =~ /\A([\s#].*|\s*)\Z/ 

        if line =~ /\A([A-Z]+)\s*=\s*(.*)\Z/
          @environment[$1] = $2
        else
          @records << CrontabRecord.parse(line)
        end
      }
    end

  end

  class CrontabFormatError < StandardError; end

  class CrontabRecord

    WDAY = %w(sun mon tue wed thu fri sat)

    SHORTCUTS = {
       "(?:year|annual)ly"  => "0 0 1 1 *",
       "monthly"          => "0 0 1 * *",
       "weekly"           => "0 0 * * 0",
       "(?:daily|midnight)" => "0 0 * * *",
       "hourly"           => "0 * * * *"
    }

    def self.parse(str)
      if str =~ /\A(?:(?:\S+\s+){5}|@(?:#{SHORTCUTS.keys.join("|")})\s+)(.*)\Z$/

        # pick off the last match
        command = $+

        # replace any shortcuts
        SHORTCUTS.collect{|shortcut, snippet| str.sub!(/\A\s*@#{shortcut}/, snippet)}

        min, hour, mday, mon, wday = str.split(/\s+/).first(5)
        
        wday = wday.downcase.gsub(/#{WDAY.join("|")}/){
          WDAY.index($&)
        }

        self.new(min, hour, mday, mon, wday, command)
      else
        raise CrontabFormatError, "Badly formatted line: #{str.inspect}"
      end
    end

    attr_reader :min, :hour, :mday, :mon, :wday, :command

    def initialize(min, hour, mday, mon, wday, command)
      @min  = parse_field(min,  0, 59)
      @hour = parse_field(hour, 0, 23)
      @mday = parse_field(mday, 1, 31)
      @mon  = parse_field(mon,  1, 12)
      @wday = parse_field(wday, 0, 7)

      # normalize weekdays
      @wday = @wday.collect{|w| w == 7 ? 0 : w }.sort.uniq

      self.command = command
    end

    def command=(c)
      raise ArgumentError, "Commands must be a String or a Proc" unless c.is_a?(String) or c.is_a?(Proc)
      @command = c
    end

    def ready?(time = Time.now)  
      min.include?  time.min  and
      hour.include? time.hour and
      mday.include? time.mday and
      mon.include?  time.mon  and
      wday.include? time.wday
    end

    def next_due(time = Time.now)
      time -= time.sec 

      # Yes this is icky.
      time += 60 while !ready?(time)

      time
    end


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
      str.split(",").map{|r|
        r, every = r.split("/")
        every = every ? every.to_i : 1
        f,l = r.split("-")
        if f == "*"
          range = first..last
        else
          l = f if l.nil?
          # make sure we have integers, and the range goes the right way
          f,l = [f,l].collect{|n| n.to_i}.sort
          raise CrontabFormatError.new "out of range (#{f} for #{first}..#{last})" unless (first..last).include?(f)
          raise CrontabFormatError.new "out of range (#{l} for #{first}..#{last})" unless (first..last).include?(l)
          range = f..l
        end
        range.to_a.find_all{|i| (i - first) % every == 0}
      }.flatten.sort.uniq
    end

  end

end
