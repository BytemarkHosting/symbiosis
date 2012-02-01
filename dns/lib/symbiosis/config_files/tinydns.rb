require 'symbiosis/config_file'
require 'tempfile'

module Symbiosis
  module ConfigFiles
    class Tinydns < Symbiosis::ConfigFile

      ###################################################
      #
      # This method is supposed to use tinydns to check to see if the DNS
      # syntax is OK.
      #
      def ok?
        #
        # TODO: parse the tinydns file and make sure it is sane.
        #
        true 
      end

      ###################################################
      #
      # The following methods are used in the template.
      #

      #
      # Return just the first IPv4.
      #
      def ip
        ip = @domain.ipv4.first
        warn "\tUsing one IP (#{ip}) where the domain has more than one configured!" if @domain.ipv4.length > 1 and $VERBOSE
        raise ArgumentError, "No IPv4 addresses defined for this domain" if ip.nil?
        
        ip.to_s
      end
      
      #
      # Returns true if the domain has an IPv4 address configured.
      #
      def ipv4?
        !@domain.ipv4.empty?
      end

      #
      # Return just the first IPv6, in the tinydns format, i.e. in full with no colons.
      #
      def ipv6
        ip = @domain.ipv6.first
        warn "\tUsing one IP (#{ip}) where the domain has more than one configured!" if @domain.ipv6.length > 1 and $VERBOSE
        raise ArgumentError, "No IPv6 addresses defined for this domain" if ip.nil?
        ip.to_string.gsub(":","")
      end

      #
      # Returns true if the domain has an IPv6 address configured.
      #
      def ipv6?
        !@domain.ipv6.empty?
      end

      #
      # Checks to see if this domain uses the Bytemark anti-spam service,
      # described at http://www.bytemark.co.uk/nospam .
      #
      def bytemark_antispam?
        @domain.uses_bytemark_antispam?
      end

    end
      
  end

end


