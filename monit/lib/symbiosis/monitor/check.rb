require 'symbiosis/monitor/service'
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
    #   def initialize
    #   super pid_file: '/var/run/sshd.pid' # pid file to check under sysvinit
    #         # init script to call under sysvinit
    #         init_script: '/etc/init.d/ssh'
    #
    #         # process name under sysvinit.
    #         # see `grep Name /proc/<pid>/status` for the process name
    #         process_name: 'sshd',
    #
    #         # unit name under systemd
    #         unit_name: 'ssh',
    #
    #         # a set of connections (currently
    #         # Symbiosis::Monitor::TCPConnection is the only kind)
    #         # to check. If nil or empty, won't check any connections
    #         connections: [Symbiosis::Monitor::TCPConnection.new(
    #           # host , port, messages to send on connect
    #           'localhost', 22, [nil, 'SSH-2.0-OpenSSH-5.5p1\n']
    #         )]
    #
    #   #
    #   # This method is used in the TCP connection test to check the TCP
    #   # responses.
    #   #
    #   def do_response_check(responses)
    #     raise "Unexpected response '#{responses.first}'" unless responses.first =~ /^SSH/
    #   end
    #  end
    #
    #  #
    #  # If this file is called as a script, run the check.
    #  #
    #  exit SshdCheck.new.do_check if $0 == __FILE__
    class Check
      # The name of the process to check.
      attr_reader :name
      attr_reader :service

      def initialize(description)
        @service = Service.from_description(description)
        @connections = description[:connections]
        @name = description[:name] || description[:unit_name]
      end

      #
      # Checks if dpkg/apt/aptitude is running.
      #
      def self.dpkg_running?
        # Check the dpkg lock
        File.open('/var/lib/dpkg/lock', 'r+') do |fd|
          args = [Fcntl::F_WRLCK, IO::SEEK_SET, 0, 0, 0].pack('s2L2i')
          fd.fcntl(Fcntl::F_GETLK, args)
          Fcntl::F_WRLCK == args.unpack('s2L5i*').first
        end
      rescue Errno::EPERM, Errno::EACCES, Errno::EAGAIN, Errno::EINVAL
        return true
      end

      #
      # Should we run the test?
      #
      def should_ignore?
        self.class.dpkg_running?
      end

      def running?
        puts 'Checking process'
        @service.running?
      end

      def service_enabled?
        puts 'Checking service is enabled'
        @service.enabled?
      end

      def ensure_service_enabled
        return SystemExit::EX_OK if should_be_enabled? == service_enabled?

        if should_be_enabled?
          return SystemExit::EX_UNAVAILABLE if @service.enable
        else
          return SystemExit::EX_UNAVAILABLE if @service.disable
        end
        SystemExit::EX_OK
      end

      def ensure_service_running
        return SystemExit::EX_OK if should_be_running? == running?

        if should_be_running?
          return SystemExit::EX_TEMPFAIL unless start
        else
          return SystemExit::EX_TEMPFAIL unless stop
          SystemExit::EX_OK
        end
      rescue Errno::EACCES, Errno::EPERM => err
        puts "Process check failed: #{err}"
        SystemExit::EX_NOPERM
      rescue => err
        puts "Process check failed: #{err}"
        SystemExit::EX_SOFTWARE
      end

      # This tests a TCP connection and the responses it receives. It takes
      # a single argument of a Symbiosis::Monitor::TCPConnection object
      def check_connection(connection)
        puts "Testing connection to #{connection.host}:#{connection.port}"
        connection.do_check
        do_response_check(connection.responses)
        puts 'Connection test OK'
        SystemExit::EX_OK
      rescue Errno::ETIMEDOUT, Errno::ECONNREFUSED, Errno::EPROTO, IOError,
             Errno::EIO => err
        puts "Connection test temporarily failed: #{err}"
        SystemExit::EX_TEMPFAIL
      rescue => err
        puts "Connection test failed: #{err}"
        SystemExit::EX_SOFTWARE
      end

      def restart
        stop
        start
      end

      def stop
        return if should_ignore?

        puts "Attempting to stop #{@name}"
        @service.stop
      end

      def start
        return if should_ignore?

        puts "Attempting to start #{@name}"
        @service.start
      end

      def check_connections
        unless @connections.nil?
          results = @connections.map do |connection|
            check_connection(connection)
          end

          fails = results.reject { |r| r == SystemExit::EX_OK }
          restart if fails.first == SystemExit::EX_TEMPFAIL
          return fails.first unless fails.empty?
        end
        SystemExit::EX_OK
      end

      def do_check
        return SystemExit::EX_UNAVAILABLE unless ensure_service_enabled

        return SystemExit::EX_TEMPFAIL unless ensure_service_running

        return SystemExit::EX_OK unless should_be_running?

        check_connections
      end

      # override this method to inspect and validate responses
      def do_response_check(_connection)
        true
      end

      # override this method for more control over enabled state
      def should_be_enabled?
        should_be_running?
      end

      # override this method for more control over running state
      def should_be_running?
        true
      end
    end
  end
end
