require 'symbiosis/firewall/pattern'
require 'symbiosis/firewall/directory'
require 'symbiosis/firewall/blacklist_db'
require 'symbiosis/firewall/logtail'

module Symbiosis
  module Firewall
    class Blacklist

      #
      # The number of matches required for a blacklist entry to be activated.  Defaults to 20.
      #
      attr_reader :block_after

      #
      # Returns the base directory.  Defaults to /etc/symbiosis/firewall.
      #
      attr_reader :base_dir

      #
      # The name of the logtail database,  Defaults to /var/lib/symbiosis/firewall-blacklist-logtail.db.
      #
      attr_reader :logtail_db

      #
      # Sets up a new Symbiosis::Firewall::Blacklist.
      #
      def initialize()
        @block_after     = 10
        @block_all_after = 25
        @base_dir     = '/etc/symbiosis/firewall'
        @logtail_db   = '/var/lib/symbiosis/firewall-blacklist-logtail.db'
        @count_db     = BlacklistDB.new('/var/lib/symbiosis/firewall-blacklist-count.db')
        @patterns     = []
      end

      #
      # Sets the base directory.  Raises Errno::ENOENT if the directory doesn't exist.
      #
      def base_dir=(dir)
        raise Errno::ENOENT, dir unless File.directory?(dir)

        @base_dir = dir
      end

      #
      # Sets the filename of logtail database. This is where offsets are
      # recorded for the various logfiles parsed.
      #
      def logtail_db=(db)
        @logtail_db = db
      end
      
      #
      # This generates the blacklist.  It returns a hash with IP addresses as
      # keys, and arrays of ports as values.
      #
      def generate
        results = do_read
        do_parse(results)
      end

      #
      # This sets the number of attempts needed to trigger blacklisting for this pattern.  Its
      # argument should be an Integer, and raises an ArgumentError if not.
      #
      def block_after=(a)
        raise ArgumentError, "#{a.inspect} must be an integer" unless a.is_a?(Integer)
        @block_after = a
      end

      def block_all_after=(a)
        raise ArgumentError, "#{a.inspect} must be an integer" unless a.is_a?(Integer)
        @block_all_after = a
      end

      private

      def do_read
        Dir.glob(File.join(@base_dir, "patterns.d", "*.patterns")) do |entry|
          @patterns << Pattern.new(entry)
        end

        logfiles = Hash.new
        results = Hash.new{|h,k| h[k] = Hash.new{|i,l| i[l] = 0}}

        @patterns.each do |pattern|
          if pattern.logfile.nil?
            puts "No logfile set in #{pattern.filename} -- ignoring." if $VERBOSE
            next
          end

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
        timestamp = Time.now.to_i

        results.each do |ip, ports|
          #
          # tot up on a per-ip basis
          #
          total_for_ip = 0

          ports.each do |port, hits|
            total_for_ip += hits

            blacklist[ip] << port if hits > @block_after
          end

          #
          # Record our count
          #
          @count_db.set_count_for(ip, total_for_ip, timestamp)

          #
          # Get the hits for the last 24 hours
          #
          total_for_ip = @count_db.get_count_for(ip, timestamp - 86400)

          #
          # If an IP has exceeded the number of matches, block it from all ports.
          #
          if total_for_ip > @block_all_after
            blacklist[ip] = %w(all)
          end

        end

        blacklist
      end

    end

  end

end


