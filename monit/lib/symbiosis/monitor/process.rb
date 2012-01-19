
module Symbiosis
    module Monitor
      class Process

        attr_accessor :initscript
        attr_writer :pidfile, :name

        def initialize
          @pidfile = nil
          @name = nil
          @initscript = nil
          @sleep = 30
        end

        def pid
          raise ArgumentError, "pidfile not set" if @pidfile.nil?
          begin
            #
            # Try to read the pidfile
            #
            pid = File.open(@pidfile,'r'){|fh| fh.read}.chomp
            #
            # Sanity check the PID found.
            #
            raise ArgumentError, "Bad PID in #{@pidfile}" unless pid =~ /^\d+$/
            return pid

          rescue Errno::ENOENT
            #
            # pidfile missing...
            #
            return nil
          end
        end
        
        def name
          pid = self.pid
          raise "Cannot find pid" if pid.nil?

          statusfile = File.join("", "proc", pid, "status")

          #
          # Raise a no-such-process error if the status file doesn't exist.
          #
          raise Errno::ESRCH, self.pid unless File.exists?(statusfile)

          #
          # Read the status file and find the name.
          #
          name = nil
          File.readlines(statusfile, 'r').find{|l| l.chomp =~ /^Name:\s+(.*)$/ }
          name = $1 unless $1.nil?

          raise Errno::ESRCH, self.pid if name.nil?

          name
        end
        
        def start
          do_initscript("start")
          @sleep.times do
            begin
              break unless self.pid.nil?
              sleep 1
            rescue ArgumentError, Errno::ESRCH
              # do nothing.. We're only going to do this a maximum of @sleep
              # times.
            end
          end
        end

        def stop
          do_initscript("stop")

          @sleep.times do
            begin
              # check the PID but do nothing. We're only going to do this a
              # maximum of @sleep times.  Programme has stopped if the PID is
              # nil.
              #
              break if self.pid.nil?
              sleep 1
            rescue ArgumentError, Errno::ESRCH
              break
            end
          end 
        end

        def is_running?

        end

        def check_initscript
          raise Errno::ENOENT, initscript unless File.exists?(initscript)
          raise Errno::EPERM,  initscript unless File.executable?(initscript)
        end

        #
        # Run the initscript
        #
        def do_initscript(action)
          return unless 0 == ::Process.uid
          check_initscript
          Kernel.system("#{initscript} #{action} 2>&1")
        end

        #
        # This checks to make sure the PID matches an expected name.
        #
        def do_check(n)
          raise Errno::ESRCH, self.pid unless n == self.name
        end

      end
    end
end
