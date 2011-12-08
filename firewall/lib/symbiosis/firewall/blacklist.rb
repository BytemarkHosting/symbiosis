require 'symbiosis/firewall/pattern'
require 'symbiosis/firewall/directory'
require 'symbiosis/firewall/logtail'

module Symbiosis
  module Firewall
    class Blacklist

      attr_reader :attempts, :base_dir, :logtail_db

      def initialize()
        @attempts     = 20
        @base_dir     = '/etc/symbiosis/firewall'
        @logtail_db   = '/var/lib/symbiosis/firewall-logtail.db'
        @patterns     = []
      end

      def base_dir=(b)
        raise Errno::ENOENT, b unless File.directory?(b)

        @base_dir = b
      end

      def logtail_db=(db)
        @logtail_db = db
      end
      
      def generate
        results = do_read
        do_parse(results)
      end

      def attempts=(a)
        raise ArgumentError, "#{a.inspect} must be an integer" unless a.is_a?(Integer)
        @attempts = a
      end

      private

      def do_read
        Dir.glob(File.join(@base_dir, "patterns.d", "*.patterns")) do |entry|
          @patterns << Pattern.new(entry)
        end

        logfiles = Hash.new
        results = Hash.new{|h,k| h[k] = Hash.new{|i,l| i[l] = 0}}

        @patterns.each do |pattern|
          #
          # Read the log file, if needed.
          #
          unless logfiles.has_key?(pattern.logfile)
            loglines = []

            begin
              logtail = Logtail.new(pattern.logfile, @logtail_db)
              loglines = logtail.readlines
            rescue Errno::ENOENT => err
              #
              # Do nothing if the log file doesn't exist.
              #
            end
            #
            # Cache the log lines that we found
            #
            logfiles[pattern.logfile] = loglines
          else
            loglines = logfiles[pattern.logfile]
          end


          #
          # Apply our pattern
          #
          new_results = pattern.apply(loglines)

          #
          # And add it on to our results.
          #
          new_results.each do |ip, ports|
            ports.each do |port, hits|
             results[ip][port] += hits
            end
          end
        end

        results
      end

      def do_parse(results = do_read)
        #
        # This is our result.  It is keyed on IP, and the values are an array
        # of ports, or an array containing "all" for all ports.
        #
        blacklist = Hash.new{|h,k| h[k] = []}

        results.each do |ip, ports|
          #
          # tot up on a per-ip basis
          #
          total_for_ip = 0

          ports.each do |port, hits|
            total_for_ip += hits

            blacklist[ip] << port if hits > @attempts
          end

          #
          # If an IP has exceeded the number of attempts on any port, block it from all ports.
          #
          if total_for_ip > @attempts
            blacklist[ip] = %w(all)
          end

        end

        blacklist
      end

    end

  end

end


