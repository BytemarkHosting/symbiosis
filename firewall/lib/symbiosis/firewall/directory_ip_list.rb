require 'symbiosis/firewall/rule'

#
# This class allows a directory containing IP addresses to be used
# to construct either a whitelist or a blacklist of the IP addresses
# which are in that directory.
#
# For example the following directory tree will blacklist all incoming
# connections from the IP addresses 1.2.3.4, 1.4.4.4, and 10.20.30.40:
#
# .
# |--- 10.20.30.40
# |---  1.2.3.4
# \--   1.4.4.4
#
# 0 directories, 3 files
#
#
#

module Symbiosis
  class Firewall
    class DirectoryIPList

      attr_reader :directory
      attr_reader :ips



      #
      #  Read all the IP files in a given directory and store them within
      # our list.
      #
      def initialize( directory )

        @directory = directory
        @ips       = Array.new()

        raise Errno::ENOENT, directory unless File.directory?( directory );

        #
        #  Read the contents of the directory
        #
        Dir.entries( directory ).each do |file|

          #
          #  Skip "dotfiles".
          #
          next if ( file =~ /^\./ )

          #
          #  Here we need to strip the optional ".auto" suffix.
          #
          if ( file =~ /(.*)\.auto$/i )
            file = $1.dup
          end

          #
          #  Save it away.
          #
          @ips.push( file )
        end
      end


      #
      #  Generate appropriate IPtable rules for a whitelist
      #
      def whitelist
        @ips.collect{|ip| Firewall::Rule.whitelist( ip ) }
      end


      #
      #  Generate appropriate IPtable rules for a blacklist
      #
      def blacklist
        @ips.collect{|ip| Firewall::Rule.blacklist( ip ) }
      end
    end
  end
end


