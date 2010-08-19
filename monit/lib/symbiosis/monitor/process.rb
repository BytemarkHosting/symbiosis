
module Symbiosis
    module Monitor
      class Process

        attr_accessor :initscript
        attr_writer :pidfile

        def initialize
          @pidfile = nil
          @name = nil
          @pid = nil
          @initscript = nil
          @sleep = 30
        end

        def pid
          return @pid unless @pid.nil?
          raise "pidfile not set" if @pidfile.nil?
          @pid = File.open(@pidfile,'r'){|fh| fh.read}.chomp
        end
        
        def name
          return @name unless @name.nil?
          raise "Cannot find pid" if self.pid.nil?

          File.open(File.join("", "proc", self.pid.to_s, "status"), 'r') do |fh|
            while @name.nil? do
              @name = $1 if fh.gets =~ /^Name:\s+(.*)$/
              break if fh.eof?
            end
          end
          @name
        end
        
        def start
          @pid = nil
          do_iniscript("start")
          @sleep.times do
            begin
              sleep 1
              break unless self.pid.nil?
            rescue
              # do nothing.. We're only going to do this a maximum of @sleep
              # times.
            end
          end
        end

        def stop
          pid_test = true
          begin
            self.pid
          rescue
            # Hmmm.. We couldn't get the current PID.  So we're not going to be
            # able to do the PID test later. 
            pid_test = false
          ensure
            do_iniscript("stop")
          end

          @sleep.times do
            begin
              # check the PID but do nothing. We're only going to do this a
              # maximum of @sleep times.
              sleep 1
              break if stop_test and self.pid.nil?
            rescue
              break
            end
          end 
        end

        def check_initscript
          raise Errno::ENOENT, initscript unless File.exists?(initscript)
          raise Errno::EPERM,  initscript unless File.executable?(initscript)
        end

        def do_iniscript(action)
          check_initscript
          @pid = nil
          Kernel.system("#{initscript} #{action} 2>&1")
        end

        def do_check(n)
          raise Errno::ESRCH, "PID #{self.pid} appears to be #{self.name}, not #{n}." unless self.name == n
        end
      end
    end
end
