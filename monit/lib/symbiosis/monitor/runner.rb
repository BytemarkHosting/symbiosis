require 'log4r'
require 'socket'
require 'erb'
require 'time'
require 'symbiosis/monitor/state_db'
require 'symbiosis/monitor/test'
require 'symbiosis/monitor/check'

module Symbiosis

  module Monitor

    class Runner

      attr_reader   :start_time, :finish_time, :template_dir
      attr_accessor :send_mail

      def initialize(dir = "/etc/symbiosis/monit.d", state_db_fn = "/var/lib/symbiosis/monit.db", template_dir = "/usr/share/symbiosis/monitor/" )
        @dir          = dir
        raise "Test directory #{dir} not found" unless File.directory?(dir)
        @state_db_fn  = state_db_fn
        @template_dir = template_dir
        raise "Template directory #{template_dir} not found" unless File.directory?(template_dir)
        self.reset
      end

      def tests
        return @tests unless @tests.empty?

        #
        # Work out which tests we're going to do
        #
        scripts = Dir.glob(File.join(@dir,"*")).collect{|t| File.basename(t)}
        scripts.reject!{|t| t !~ /^[a-z0-9][a-z0-9-]*$/}
        @tests = scripts.sort.collect{|t| Symbiosis::Monitor::Test.new(File.join(@dir,t), self.state_db)}
      end

      def reset
        @tests        = []
        @start_time   = nil
        @finish_time  = nil
      end

      def logger
        @logger ||= Log4r::Logger.new(self.class.to_s)
      end

      def dpkg_running?
       Symbiosis::Monitor::Check.dpkg_running?
      end

      def state_db
        @state_db ||= Symbiosis::Monitor::StateDB.new(@state_db_fn)
      end

      def hostname
        Socket.gethostname
      end

      def go
        @start_time = Time.now
        logger.debug("STARTING")

        self.tests.each do |test|
          begin
            result = test.run
            raise result unless test.success?
            if test.retried
              result.backtrace.each{ |l| logger.info("#{test.name}: #{l}") }
              logger.warning("#{test.name}: PASSED")
            else
              result.backtrace.each{ |l| logger.debug("#{test.name}: #{l}") }
              logger.debug("#{test.name}: PASSED")
            end
          rescue SystemExit => err
            #
            # Log the backtrace if we've failed.
            #
            err.backtrace.each{ |l| logger.info("#{test.name}: #{l}") }

            #
            # If we get a temporary failure, retry!
            #
            if ( SystemExit::EX_TEMPFAIL == err.to_i and not test.retried )
              logger.warning("#{test.name}: RETRYING (following #{err.to_s})")
              retry
            end

            # 
            # Otherwise do nothing.
            #
            logger.warning("#{test.name}: FAILED: #{err.to_s}")
          rescue RuntimeError => err
            error err.to_s
          end

        end

        logger.info("RESULT: #{successful_tests.length}/#{tests.length} passed.")
        @finish_time = Time.now

        nil
      end

      def failed_tests
        tests - successful_tests
      end

      def retried_tests
        tests.select{|t| t.retried?}
      end

      def usage_fail_tests
        tests.select{|t| [SystemExit::EX_USAGE, SystemExit::EX_CONFIG, 126, 127].include?(t.exitstatus.to_i)}
      end

      def successful_tests
        tests.select{|t| t.success?}
      end

      def should_notify?
        $VERBOSE or tests.any?{|t| t.just_failed? or t.just_succeeded?}
      end

      def report(template_fn="default")
        template_fn += ".txt.erb"
        template = File.read(File.join(@template_dir, template_fn))
        ERB.new(template,0,'%<>').result(binding)
      end

    end

  end

end
