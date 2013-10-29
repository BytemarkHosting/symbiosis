require 'symbiosis/config_file'
require 'symbiosis/domain/dns'
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

      class Eruby < ::Erubis::Eruby
        include Erubis::EscapeEnhancer
        include Erubis::PercentLineEnhancer

        #
        # Encodes a given string into a format suitable for consupmtion by TinyDNS
        #
        def escaped_expr(code)
          return "tinydns_encode(#{code.strip})"
        end

      end
      
      self.erb = Eruby

      #
      # Encodes a string for TinyDNS.
      #
      def tinydns_encode(s)
        #
        # All bytes between 32 and 126, except hash (comment) and colon (field delimiter)
        #
        ok_bytes = ((32..126).to_a - [35, 58])
        s.to_s.bytes.collect do |b|
          (ok_bytes.include?(b) ? b.chr : ("\\%03o" % b))
        end.join
      end

      #
      # Decodes a given string from a format suitable for consupmtion by TinyDNS
      # 
      def tinydns_decode(s)
        s.gsub(/(?:\\([0-7]{3,3})|.)/){|r| $1 ? [$1.oct].pack("c*") : r}
      end

    end
      
  end

end


