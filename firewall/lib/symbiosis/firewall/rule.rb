require 'symbiosis/firewall/ipaddr'
require 'symbiosis/firewall/ports'
require 'erb'

module Symbiosis
  class Firewall
    #
    #  This class encapsulates a single firewall (iptables) rule.
    #
    class Rule

      #
      # Nice class variable..
      #
      @@ports = Ports.new

      attr_reader :name
      attr_reader :port
      attr_reader :jump
      attr_reader :jump_opts
      attr_reader :chain
      attr_reader :address

      #
      #  Constructor
      #
      def initialize( name )
        #
        # Some defaults..
        #
        @chain = "INPUT"
        @jump      = "ACCEPT"
        @jump_opts = nil
        @address   = nil
        @port      = nil
        @template  = nil
        @template_dir = '/usr/share/symbiosis/firewall'
        @name      = name
        @port      = @@ports.lookup( @name ) unless @name.nil? 
      end

      #
      #  Helper:  Note no port is required for a blacklist.
      #
      def self.blacklist( ip )
        f = self.new( "blacklist-#{ip}" )
        f.incoming()
        f.address( ip )
        f.deny()
        return f
      end

      #
      #  Helper:  Note no port is required for a whitelist.
      #
      def self.whitelist( ip )
        f = self.new( "whitelist-#{ip}" )
        f.incoming()
        f.address( ip )
        f.permit()
        return f
      end

      def permit
        @jump = "ACCEPT"
      end

      def deny
        @jump = "DROP"
      end

      #
      #  Set this rule to work against incoming connections.
      #
      def incoming
        @chain = "INPUT"
      end

      #
      #  Is this incoming?
      #
      def incoming?
        return( @chain == "INPUT" )
      end

      #
      # Set this rule to work against outgoing connections.
      #
      def outgoing
        @chain = "OUTPUT"
      end

      #
      #  Is this an outgoing rule?
      #
      def outgoing?
        ( @chain == "OUTPUT" )
      end

      #
      # Return either "incoming" or "outgoing" depending on chain
      #
      def direction
        return "incoming" if incoming? 
        return "outgoing" if outgoing?
        #
        # Hmm neither incoming or outgoing!
        #
        nil
      end

      #
      # Is this an IPv6 rule
      #
      def ipv6?
        @address.nil? or (@address.is_a?(IPAddr) and @address.ipv6?)
      end
    
      def ipv4?
        @address.nil? or (@address.is_a?(IPAddr) and @address.ipv4?)
      end

      #
      # Return the correct iptables command for the protocol
      #
      def iptables_cmds
        cmds = %w(iptables ip6tables)
        cmds.delete("ip6tables") if self.ipv4?
        cmds.delete("iptables")  if self.ipv6?
        cmds.collect{|c| "/sbin/#{c}"}
      end

      #
      # The meat of the code.  This is designed to return the
      # actual "iptables" command which this rule can be used
      # to generate.
      #
      def to_s()
        #
        # Detect if this is a legacy-style rule, or an ERB one. 
        #
        if template =~ /\$(SRC|DEST)/
          lines = template.split("\n")
          if ipv6? and lines.any?{|l| l =~ /^[^#]*iptables /}
            warn "Disabling IPv4 rules for IPv6 addresses in #{@name}" if $VERBOSE
            lines = lines.collect{|l| l =~ /^[^#]*iptables / ? "# "+l : l }
          end
          lines = lines.collect{|l| l.gsub("$SRC",src).gsub("$DEST",dst)}
          return lines.join("\n") 
        else
          return ERB.new(template,0,'%>').result(binding)
        end
      end


      #
      #  Set the source
      #
      def address=( new_address )
        @address = IPAddr.new(new_address)
      end

      def src
        return "" if @address.nil?
        "--src #{@address}"
      end

      alias source src

      def dst
        return "" if @address.nil?
        "--dst #{@address}"
      end

      alias destination dst

      def port=( new_port )
        @port = new_port
      end

      #
      #  Is there a template for this rule?
      #
      def template
        return @template unless @template.nil?

        fn = "#{@template_dir}/#{@name}.#{direction}"
        if ( File.exists?( fn ) )
          @template = File.read(fn)
        else
          @template =<<EOF
% iptables_cmds.each do |cmd|
% %w(tcp udp).each do |proto|
<%= cmd %> -A <%= chain %>
% unless port.nil?
 -p <%= proto %> --dport <%= port %>
%  end
% if incoming?
 <%= src %>
% else
 <%= dst %>
% end
 -j <%= jump %>

% break unless port
% end
% end
EOF
        end
        @template
      end

      #
      # Allow us to set a template (for testing mostly).
      #
      def template=(t)
        @template = t
      end

      def template_dir=(td)
        @template_dir = td
      end

    end

  end
end
