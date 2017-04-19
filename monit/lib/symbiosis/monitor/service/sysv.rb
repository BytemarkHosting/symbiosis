module Symbiosis
  module Monitor
    # for inspecting and altering a process started by an init script under
    # sysvinit and compatible inits
    class SysvService
      # description requires a :pid_file and an :init_script, both of which are
      # full path. The pid file must be made when the service is started.
      # if :process_name is provided, running? will make sure the process it
      # finds has that name.
      def initialize(description)
        @pidfile = description[:pid_file]
        @initscript = description[:init_script]
        @expectedname = description[:process_name]
      end

      def start
        do_initscript('start')
      end

      def stop
        do_initscript('stop')
      end

      def running?
        name =~ /#{expected_name}/
      rescue Errno::ESRCH
        false
      end

      private

      def pid
        raise ArgumentError, 'pidfile not set' if @pidfile.nil?
        begin
          #
          # Try to read the pidfile
          #
          pid = File.open(@pidfile, 'r', &:read).chomp
          #
          # Sanity check the PID found.
          #
          raise ArgumentError, "Bad PID in #{@pidfile}" unless pid =~ /^\d+$/
          pid
        rescue Errno::ENOENT
          #
          # pidfile missing...
          #
          nil
        end
      end

      def name
        pid = self.pid
        raise Errno::ENOENT if pid.nil?

        # Raise a no-such-process error if the status file doesn't exist.
        raise Errno::ESRCH, pid unless File.exist?(status_file)

        # Read the status file and find the name.
        File.readlines(status_file).find { |l| l.chomp =~ /^Name:\s+(.*)$/ }
        name = Regexp.last_match(1)

        raise Errno::ESRCH, pid if name.nil?

        name
      end

      def status_file
        File.join('', 'proc', pid, 'status')
      end

      def check_initscript
        raise Errno::ENOENT, initscript unless File.exist?(initscript)
        raise Errno::EPERM,  initscript unless File.executable?(initscript)
      end

      #
      # Run the initscript
      #
      def do_initscript(action)
        return unless ::Process.uid.zero?
        check_initscript
        Kernel.system("#{initscript} #{action} 2>&1")
      end
    end
  end
end
