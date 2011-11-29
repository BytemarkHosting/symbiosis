module Symbiosis

  module Monitor

    class Test

      attr_reader :name, :retried, :exitstatus, :timestamp

      def initialize(script, state_db)
        @script   = script
        @state_db = state_db
        @name     = File.basename(script)
        self.reset
      end
 
      def logger
        @logger ||= Lo4r::Logger.new(self.class.name)
      end

      def last_result
      end

      def output
        @output.join("\n")
      end

      def exitstatus
        @exitstatus
      end

      def just_failed?
        false == success? and
          (0 == @last_exitstatus or @last_exitstatus.nil?)
      end
      
      def just_succeeded?
        true == success? and
          0 != @last_exitstatus
      end

      def reset
        @retried  = nil
        @output   = []
        @exitstatus = nil
        #
        # Set up the test using the last result
        #
        lr = @state_db.last_result_for(name)
        if lr.nil?
          @last_exitstatus = nil
        else
          @last_exitstatus = lr['exitstatus']
        end
      end

      def run
        if @retried.nil?
          @retried = false
        else
          @retried = true
        end

        @timestamp = Time.now

        @output = []
        pid = nil
        IO.popen(@script +" 2>&1") do |pipe|
          pid = pipe.pid
          @output << pipe.gets.to_s.chomp while !pipe.eof?
        end

        #
        # Sanity checks...
        #
        status = $?
        raise RuntimeError, "Somehow the command #{@script} didn't execute." unless status.is_a?(::Process::Status)
        raise RuntimeError, "Process IDs didn't match when checking #{@script}." if pid != status.pid

        @exitstatus = SystemExit.new(status.exitstatus)
        @exitstatus.set_backtrace @output

        #
        # Record the answer.
        #
        @state_db.record(name, @exitstatus.to_i, @output.join("\n"))

        return @exitstatus
      end

      def success?
        return nil if @exitstatus.nil?
        @exitstatus.to_i == 0
      end

      def retried?
        @retried
      end

    end

  end

end
