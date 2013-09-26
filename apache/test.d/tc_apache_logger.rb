#!/usr/bin/ruby
#
#
require 'symbiosis/apache_logger'
require 'socket'
require 'test/unit'

class TestApacheLogger < Test::Unit::TestCase

  def setup
    @prefix = ENV['TMP'] || "/tmp"

    #
    #  Create the domain
    #
    @domain1 = Symbiosis::Domain.new(nil, @prefix)
    @domain1.create()

    @domain2 = Symbiosis::Domain.new(nil, @prefix)
    @domain2.create()

  end

  def teardown
    #
    #  Delete the temporary domain
    #
    @domain1.destroy() unless @domain1.nil?
    @domain2.destroy() unless @domain2.nil?
  end

  #
  # Not sure if this is a good thing to do.
  #
  def eventmachine(timeout = 1)
    Timeout::timeout(timeout) do
      EM.run do
        yield
      end
    end
  rescue Timeout::Error
    flunk 'Eventmachine was not stopped before the timeout expired'
  end

  def test_logging
    test_lines = [ [@domain1, "foo"],
                   [@domain2, "bar"] ]

    self.eventmachine do
      r,w = IO.pipe

      logger = EM.attach(r, Symbiosis::ApacheLogger) do |l|
        l.sync_io = true
        l.prefix = @prefix
      end

      #
      # This is what we do to test
      #
      test_proc = proc {
       test_lines.each do |d, l|
         w.puts "#{d.name} #{l}"
        end
      }

      #
      # Then, we run our asserts
      #
      assert_proc = proc {
        #
        # If we get this far, open the domain's access logs and look for foo and bar.
        #
        test_lines.each do |d, l|
          # Make sure the file exists
          access_log = File.join(d.log_dir, "access.log")
          assert(File.exists?(access_log), "Access log #{access_log} for #{d.name} not found")
    
          # And that we can read it.
          line = File.readlines(access_log).first.to_s.chomp
          assert_equal(line, l)
        end
        EM.stop
      }

      EM.defer(test_proc, assert_proc)
    end

  end

end
