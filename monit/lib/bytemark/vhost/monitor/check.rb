require 'bytemark/vhost/monitor/process'
require 'bytemark/vhost/monitor/tcpconnection'
require 'systemexit'

module Bytemark
  module Vhost
    module Monitor
      class Check
        attr_reader :name

        def initialize
          @process = Bytemark::Vhost::Monitor::Process.new
        end


        #
        #  Should we ignore failures because apt-get|aptitude|dpkg is running?
        #
        def should_ignore?
          found = false

          return true if ( File.exists?( "/tmp/dpkg.running" ) )

          Dir.foreach("/proc/") do |entry|
            if ( File.directory?( "/proc/#{entry}" ) && ( entry =~ /([0-9]+)/ ) )
              File.open( "/proc/#{entry}/cmdline", "r") do |infile|
                begin
                  while (line = infile.gets)
                    line.chomp!
                    if ( line =~ /(apt|bytemark-vhost-updater|dpkg|apt-get|aptitude|debconf)/i )
                      found = true
                      puts "apt-get|aptitude|dpkg|debconf are running..."
                    end
                  end
                rescue
                end
              end
            end
          end
          found
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
            puts "#{@name} doesn't appear to be runing: "+err.to_s
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
        # a single argument of a Bytemark::Vhost::Monitor::TCPConnection object
        def do_tcpconnection_check(connection)
          raise ArgumentError unless connection.is_a?(Bytemark::Vhost::Monitor::TCPConnection)
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
end

