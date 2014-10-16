#!/usr/bin/ruby
#
#
require 'symbiosis/apache_logger'
require 'socket'
require 'test/unit'
require 'tmpdir'
require 'tempfile'

class TestApacheLogger < Test::Unit::TestCase

  def setup
    @prefix = Dir.mktmpdir("srv")
    File.chown(1000,1000,@prefix)

    @default_log = Tempfile.new("tc_apache_logger", @prefix)
    @default_filename = @default_log.path

    @domains = []

  end

  def teardown
    #
    #  Delete the temporary domain
    #
    @domains.each{|d| d.destroy() unless d.nil? }

    #
    # Close + remove our default logfile
    #
    @default_log.close if @default_log.is_a?(Tempfile)

    #
    # Remove the @prefix directory
    #
    FileUtils.remove_entry_secure @prefix
  end

  #
  # Not sure if this is a good thing to do.
  #
  def eventmachine(timeout = 30)
    Timeout::timeout(timeout) do
      #
      # Catch all eventmachine errors
      #
      EM.error_handler{ |e|
        flunk (["Error raised during EM loop: #{e.message}: #{e.to_s}"]+e.backtrace).join("\n")
      }

      EM.run do
        yield
      end
    end
  rescue Timeout::Error
    flunk 'Eventmachine was not stopped before the timeout expired'
  end

  #
  # This tests the options we can set.
  #
  def test_setup
    {:sync_io => false,
     :prefix  => "foo",
     :max_filehandles => 100,
     :log_filename => "foo.log",
     :default_filename => "/var/log/apache2/test.log",
     :uid => 100,
     :gid => 200 }.each do |option, value|
      l = nil
      assert_nothing_raised("Exception raised when setting #{option.to_s} to #{value.inspect} in Symbiosis::ApacheLogger") {
        l = Symbiosis::ApacheLogger.new($0, {option => value})
      }
      assert_equal(value, l.__send__(option), "Wrong value returned for #{option.to_s} in Symbiosis::ApacheLogger")
    end

    assert_raise(ArgumentError){
      Symbiosis::ApacheLogger.new($0, {:made_up_arg => "barf"})
    }
  end

  def test_domain_caching
    domain = Symbiosis::Domain.new(nil, @prefix)
    domain.create
    name = domain.name
    times = []

    clock = Proc.new { times.shift }
    cache = Symbiosis::ApacheLogger::DomainCache.new(@prefix, 10, clock)

    times += [0]
    assert(cache[name],
      "Symbiosis::ApacheLogger::DomainCache failed to find domain")
 
    domain.destroy

    times += [1]
    assert(cache[name],
      "Symbiosis::ApacheLogger::DomainCache failed to cache domain")

    times += [100]
    assert(cache[name].nil?,
      "Symbiosis::ApacheLogger::DomainCache failed to expire cache")
  end

  def test_logging
    #
    #  Create the domain
    #
    10.times do |i| 
     @domains << Symbiosis::Domain.new("existent-#{i}.com", @prefix)
    end
    @domains.each{|d| d.create }

    #
    # We'll delete this domain half-way
    #
    to_delete = Symbiosis::Domain.new("deleted.com", @prefix)
    to_delete.create
    @domains << to_delete

    #
    # Add a non-existent domain to the mis
    #
    non_existent = Symbiosis::Domain.new("non-existent.com", @prefix)
    @domains << non_existent

    test_lines = []
    test_lines2 = []

    10.times do |i|
      test_lines  += @domains.collect{|d| [d, "#{i} " + Symbiosis::Utils.random_string(40)] }
      test_lines2 += @domains.collect{|d| [d, "#{10+i} " + Symbiosis::Utils.random_string(40)] }
    end

    args = {:sync_io => true, :prefix => @prefix, :default_filename => @default_filename, :max_filehandles => 4, :cache_time => 1}

    self.eventmachine do
      r,w = IO.pipe

      logger = EM.attach(r, Symbiosis::ApacheLogger, args)

      #
      # This is what we do to test
      #
      test_proc = proc {
        test_lines.each do |d, l|
          w.puts "#{d.name} #{l}"
        end

        EM.next_tick do
          logger.close_filehandles
          logger.resume 
        end

        sleep 1
        to_delete.destroy

        test_lines2.each do |d, l|
          w.puts "#{d.name} #{l}"
        end
      }

      #
      # Then, we run our asserts
      #
      assert_proc = proc { logger.unbind ; EM.stop }

      EM.defer(test_proc, assert_proc)
    end

    #
    # If we get this far, open the domain's access logs and look for foo and bar.  Mash the test lines into a hash.
    #
    log_line_hash = Hash.new{|h,k| h[k] = []}

    (test_lines + test_lines2).each do |d, l|
      #
      # We expect the last 10 lines of the deleted domain to appear, and all
      # the non-existent ones in the shared access log.
      #
      if [non_existent, to_delete].include?(d)
        next if to_delete == d and l =~ /^\d /
        log_line_hash[non_existent] << "#{d.name} #{l}"
      else
        log_line_hash[d] << l
      end
    end

    log_line_hash.each do |d, lines|

      if File.directory?(d.directory)
        # Make sure the file exists
        access_log = File.join(d.log_dir, "access.log")
      else
        # When we write to the default log, the domain is still attached.
        access_log = @default_filename
      end

      assert(File.exists?(access_log), "Access log #{access_log} for #{d.name} not found")
    
      # And that we can read it.
      logged_lines = File.readlines(access_log).collect{|l| l.to_s.chomp}
      assert_equal(lines, logged_lines)
    end

    assert(!File.directory?(non_existent.directory), "Non-existent domain's directory created.")
    assert(!File.directory?(to_delete.directory), "Non-existent domain's directory created.")

  end

end
