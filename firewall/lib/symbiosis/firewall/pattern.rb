
require 'symbiosis/ipaddr'

module Symbiosis
  module Firewall
    class Pattern

      attr_reader :logfile, :filename

      def initialize(filename)
        @logfile  = nil
        @ports    = nil
        @patterns = []
        @filename = filename

        File.readlines(filename).each do |line|
          #
          # Remove preceeding and trailing spaces, and newlines
          #
          line = line.strip.chomp

          next if line.empty? or line =~ /^#/ 

          #
          #  Filename
          #
          if line =~ /^file\s*=\s*(.*)/  and @logfile.nil?
            @logfile = $1

          #
          # Comma/space separated line of ports/services
          #
          elsif line =~ /^ports\s*=\s*(.*)/ and @ports.nil?
            @ports = $1.split(/[^a-z0-9]+/i)

          else
            line = line.gsub("__IP__","(?:::ffff:)?([0-9a-fA-F:\.]+(?:/[0-9]+)?)")

            # 
            # Make sure there is anchor at one end of the regexp
            #
            unless line =~ /^\^/ or line =~ /\$$/
              line += "$"
            end

            @patterns << Regexp.new(line)
          end

        end

        if @ports.nil? or @ports.empty?
          puts "No ports set in #{filename} -- assuming 'all'." if $VERBOSE
          @ports = %w(all)
        end

      end


      #
      # Takes an array of log lines, and applies it patterns.  It returns a hash of hashes:
      #
      #  {
      #    ip.ad.re.ss1 =>
      #       { port1 => count1,
      #         port2 => count2 },
      #    ip.ad.re.ss2 =>
      #       { port1 => count3,
      #         port2 => count4 },
      #  }
      #
      #
      def apply(lines)
        # This returns a has of IPs summed up.
        results = Hash.new{|h,k| h[k] = Hash.new{|i,l| i[l] = 0 }}

        lines.each do |line|
          @patterns.each do |pattern|
            next unless line =~ pattern
            ip = $1

            begin
              ip = IPAddr.new(ip)
            rescue ArgumentError
              puts "Failed to parse IP #{ip.inspect} (from #{line.inspect})." if $VERBOSE
            end

            next unless ip.is_a?(IPAddr)

            #
            # Only apply /64 for ipv6 addresses.
            #
            ip = ip.mask( 64 ) if ip.ipv6?

            @ports.each do |port|
              results[ip.to_s][port] += 1
            end
          end
        end

        results
      end

    end

  end

end

