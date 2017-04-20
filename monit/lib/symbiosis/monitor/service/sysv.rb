require 'English'
module Symbiosis
  module Monitor
    # for inspecting and altering a process started by an init script under
    # sysvinit and compatible inits
    class SysvService
	    # default runlevels to use in the abscence of info
	    START_RUNLEVELS = ['3','4','5'].freeze
      # description requires a :pid_file and an :init_script, both of which are
      # full path. The pid file must be made when the service is started.
      # if :process_name is provided, running? will make sure the process it
      # finds has that name.
      def initialize(description)
        @pidfile = description[:pid_file]
        @initscript = description[:init_script]
        @expected_name = description[:process_name] || description[:unit_name]
      end

      def start
        do_initscript('start')
      end

      def stop
        do_initscript('stop')
      end

      def running?
       name == @expected_name
      rescue Errno::ESRCH, Errno::ENOENT
        false
      end

      def enabled?
	      !rc_scripts.grep(/rc[#{START_RUNLEVELS.join}]\.d\/S/).empty?
      end

      def enable
	      puts "enabling #{initscript_name}"
	      # updated-rc.d defaults does nothing and returns 0 if scripts already exist
	      system("update-rc.d defaults #{initscript_name}") if rc_scripts.empty?
	      unless 0 == $CHILD_STATUS
		      puts 'update-rc.d failed - giving up on enabling'
		      return true
	      end
	      return false if enabled?
	      # if we're still here, rc scripts already existed but
	      # set all our runlevels to kill so let's fix that
	      rename_rc_scripts /^K/, 'S'
      end

      def disable
	      puts "disabling #{initscript_name}"
	      rename_rc_scripts /^S/, 'K'
      end

      private

      def rename_rc_scripts(pattern, replacement, runlevels=START_RUNLEVELS)
	      rc_scripts.each do |old_path|
		      dir = File.dirname(old_path)
		      if old_path =~ /^\/etc\/rc[#{runlevels.join}]\.d\/K.+$/
			      new_name = File.basename(old_path).sub pattern, replacement
			      new_path = File.join(dir, new_name)
			      puts "renaming #{old_path} to #{new_path}"
			      File.rename old_path, new_path
			else 
				puts "#{old_path} didn't match regex"
		      end
	      end
      end

      def initscript_name
	      File.basename @initscript
      end

      def rc_scripts
	      Dir.glob("/etc/rc?.d/???#{initscript_name}")
      end

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
        raise Errno::ENOENT if pid.nil?

        # Raise a no-such-process error if the status file doesn't exist.
        raise Errno::ESRCH, pid unless File.exist?(status_file)

        # Read the status file and find the name.
        File.readlines(status_file).find { |l| l.chomp =~ /^Name:\s+(.*)\s*$/ }
        name = Regexp.last_match(1)

        raise Errno::ESRCH, pid if name.nil?

        name
      end

      def status_file
        File.join('', 'proc', pid, 'status')
      end

      def check_initscript
        raise Errno::ENOENT, @initscript unless File.exist?(@initscript)
        raise Errno::EPERM,  @initscript unless File.executable?(@initscript)
      end

      #
      # Run the initscript
      #
      def do_initscript(action)
        return unless ::Process.uid.zero?
        check_initscript
	Kernel.system("service #{File.basename @initscript} #{action} 2>&1")
	$CHILD_STATUS
      end
    end
  end
end
