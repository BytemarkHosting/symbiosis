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
      attr_reader :direction
      attr_reader :address

      #
      #  Constructor
      #
      def initialize( name )
        #
        # Some defaults..
        #
        @direction = "incoming"
        @address   = nil
        @port      = nil
        @template  = nil
        @template_dirs = %w(/usr/local/share/firewall /usr/local/share/symbiosis/firewall /usr/share/firewall /usr/share/symbiosis/firewall)
        @name      = name
        @port      = @@ports.lookup( @name ) unless @name.nil? 
      end

      #
      #  Helper:  Note no port is required for a blacklist.
      #
      def self.blacklist( ip )
        f = self.new( "reject" )
        f.incoming()
        f.address = ip
        return f
      end

      #
      #  Helper:  Note no port is required for a whitelist.
      #
      def self.whitelist( ip )
        f = self.new( "accept" )
        f.incoming()
        f.address = ip 
        return f
      end

      #
      #  Set this rule to work against incoming connections.
      #
      def incoming
        @direction = "incoming"
      end

      #
      #  Is this incoming?
      #
      def incoming?
        "incoming" == @direction
      end

      #
      # Set this rule to work against outgoing connections.
      #
      def outgoing
        @direction = "outgoing"
      end

      #
      #  Is this an outgoing rule?
      #
      def outgoing?
        "outgoing" == @direction
      end

      #
      # Two convenience methods to allow us to use chain/src_or_dst for templates.
      #
      def chain
        case direction
          when "incoming"
            "INPUT"
          when "outgoing"
            "OUTPUT"
          else
            raise "Don't know which chain to choose for direction #{direction}."
        end
      end

      def src_or_dst
        case direction
          when "incoming"
            src
          when "outgoing"
            dst
          else
            raise "Don't know which src or dst to choose for direction #{direction}."
        end
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
        cmds.delete("iptables") unless self.ipv4?
        cmds.delete("ip6tables") unless self.ipv6?
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

          if !ipv4? and lines.any?{|l| l =~ /^[^#]*iptables /}
            warn "Disabling IPv4 rules for non-IPv4 addresses in #{@name}" if $VERBOSE
            lines = lines.collect{|l| l =~ /^[^#]*iptables / ? "# "+l : l }
          end

          lines = lines.collect{|l| l.gsub("$SRC",src).gsub("$DEST",dst)}

          return lines.join("\n") 
        else
          begin
            return ERB.new(template,0,'%>').result(binding)
          rescue SyntaxError => err
            warn "Caught syntax error in #{template}:"
            raise err
          end
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

        fn = nil
        
        #
        # Search all the template directories...
        #
        @template_dirs.each do |td|
          fn = "#{td}/#{@name}.#{direction}"
          next unless File.exists?(fn)

          @template = File.read(fn) 
        end

        #
        # OK we've found the template!
        #
        return @template unless @template.nil?

        #
        # OK, we've not found it.  Try using "accept", but only if one of port
        # or address is defined.  This prevents accidental ACCEPT ALL rules
        # being put in.
        #
        unless @port.nil? and @address.nil?
          @template_dirs.each do |td|
            fn = "#{td}/accept.#{direction}"
            next unless File.exists?(fn)
  
            @template = File.read(fn) 
          end
        end

        return @template unless @template.nil?

        raise ArgumentError, "Could not find #{@name}.#{direction} template"
      end

      #
      # Allow us to set a template (for testing mostly).
      #
      def template=(t)
        @template = t
      end

      #
      # If we specify a template directory, ignore all the rest.
      #
      def template_dir=(td)
        @template_dirs = [ td ]
      end

      def direction=(d)
        raise ArgumentError, "Bad direction #{d.inspect}" unless %w(incoming outgoing).include?(d)
        @direction = d
      end

    end

  end

end
