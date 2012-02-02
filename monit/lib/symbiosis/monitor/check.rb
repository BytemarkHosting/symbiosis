require 'symbiosis/monitor/process'
require 'symbiosis/monitor/tcpconnection'
require 'systemexit'
require 'fcntl'

module Symbiosis

    module Monitor

      #
      # This class is the parent class that can be used by individual service
      # tests run by symbiosis-monit.
      #
      # This class should be inherited by tests to do checks.  Currently this
      # class can check processes, TCP banners/responses, and can restart a
      # process if needed.
      #
      # An example test:
      #
      #  #
      #  # Inherit the Check class.
      #  #
      #  class SshdCheck < Symbiosis::Monitor::Check
      #   
      #   #
      #   # Return the port as needed
      #   #
      #   attr_reader :port
      # 
      #   #
      #   # Set up some defailt locations
      #   # -- the pidfile, initscript, process name and TCP port.
      #   #
      #   def initialize
      #     super
      #     @process.pidfile = "/var/run/sshd.pid"
      #     @process.initscript = "/etc/init.d/ssh"
      #     @name = "sshd"
      #     @port = 22
      # 
      #     #
      #     # See if the port can be gleaned from the SSH config. 
      #     #
      #     if ( File.exists?( "/etc/sshd/sshd_config" ) )
      # 
      #       File("file").readlines.each |l|
      #         @port = $1.to_i if l =~ /^Port\s+(\d+)/
      #     end
      #   end
      # 
      #   #
      #   # Run the check -- this overrides the default do_check class in
      #   # Symbiosis::Monitor::Check
      #   #
      #   def do_check
      #     #
      #     # Check our initscript, and return a config error if it is wrong.
      #     #
      #     return SystemExit::EX_CONFIG unless initscript_ok?
      #
      #     #
      #     # Do the process check
      #     #
      #     r = do_process_check
      #
      #     #
      #     # Restart if the process check returns a temporary error.
      #     #
      #     self.restart if SystemExit::EX_TEMPFAIL == r
      #
      #     #
      #     # Return if the process check wasn't successful.
      #     #
      #     return r unless r.successful?
      #
      #     #
      #     # Set up a TCP connection test.
      #     #
      #     tcpconnection = Symbiosis::Monitor::TCPConnection.new(
      #       "localhost", @port, [nil,"SSH-2.0-OpenSSH-4.3p2\n"]
      #     )
      #
      #     #
      #     # Run the TCP connection check, 
      #     #
      #     r = do_tcpconnection_check(tcpconnection)
      #
      #     #
      #     # Try to restart if the check returned a temporary failure.
      #     #
      #     self.restart if SystemExit::EX_TEMPFAIL == r
      # 
      #     #
      #     # Finally return the result from the TCP check.
      #     #
      #     return r
      #   end
      # 
      #   #
      #   # This method is used in the TCP connection test to check the TCP responses.
      #   #
      #   def do_response_check(responses)
      #     raise "Unexpected response '#{responses.first}'" unless responses.first =~ /^SSH/
      #   end
      # 
      #  end
      # 
      #  #
      #  # If this file is called as a script, run the check.
      #  #
      #  exit SshdCheck.new.do_check if $0 == __FILE__
      # 
      #
      #
      #  
      class Check

        #
        # The name of the process to check.
        #
        attr_reader :name

        def initialize
          @process = Symbiosis::Monitor::Process.new
        end

        #
        # Checks if dpkg/apt/aptitude is running.
        #
        def self.dpkg_running?
          begin 
            # Check the dpkg lock
            File.open('/var/lib/dpkg/lock','r+') do |fd|
              args = [Fcntl::F_WRLCK, IO::SEEK_SET, 0, 0, 0].pack("s2L2i")
              fd.fcntl(Fcntl::F_GETLK, args)
              Fcntl::F_WRLCK == args.unpack("s2L5i*").first
            end
          rescue Errno::EPERM, Errno::EACCES, Errno::EAGAIN => err
            return true
          end
        end

        #
        # Should we run the test?
        #
        def should_ignore?
          self.class.dpkg_running?
        end

        def should_be_running
          true
        end

        def running
          begin
            puts "Checking process"
            @process.do_check(@name)
            puts "Process #{@name} found with PID #{@process.pid}"
            true
         rescue Errno::EACCES, Errno::EPERM => err
            puts "Not enough permissions to check process #{@name}: "+err.to_s
            raise
         rescue => err
            puts "#{@name} doesn't appear to be running: "+err.to_s
            false
          end
        end

        def initscript_ok?
          begin
            @process.check_initscript
          rescue => err
            puts "Initscript check failed: #{err.to_s}"
            return false
          end
          true
        end

        def do_process_check
          nt     = should_be_running ? "" : " not"
          begin
            if should_be_running != running
              puts "#{@name} should#{nt} be running."
              SystemExit::EX_TEMPFAIL
            else
              puts "Process state OK -- #{@name} should#{nt} be running"
              SystemExit::EX_OK
            end
          rescue Errno::EACCES, Errno::EPERM => err
            puts "Process check failed: "+err.to_s
            SystemExit::EX_NOPERM
          rescue => err
            puts "Process check failed: "+err.to_s
            SystemExit::EX_SOFTWARE
          end
        end

        # This tests a TCP connection and the responses it receives.  It takes
        # a single argument of a Symbiosis::Monitor::TCPConnection object
        def do_tcpconnection_check(connection)
          raise ArgumentError unless connection.is_a?(Symbiosis::Monitor::TCPConnection)
          begin
            puts "Testing connection to #{connection.host}:#{connection.port}"
            connection.do_check
            do_tcpresponse_check(connection.responses)
            puts "Connection test OK"
            SystemExit::EX_OK
          rescue Errno::ETIMEDOUT,
                 Errno::ECONNREFUSED,
                 Errno::EPROTO,
                 IOError, Errno::EIO => err
            puts "Connection test temporarily failed: "+err.to_s
            SystemExit::EX_TEMPFAIL
          rescue => err
            puts "Connection test failed: "+err.to_s
            SystemExit::EX_SOFTWARE
          end
        end

        def restart
          return if ( should_ignore? )

          self.stop
          self.start
        end

        def stop
          return if ( should_ignore? )

          puts "Attempting to stop #{@name}"
          @process.stop
        end

        def start
          return if ( should_ignore? )

          puts "Attempting to start #{@name}"
          @process.start
        end

        def do_tcpresponse_check(responses)
          true
        end
      end
    end
end

