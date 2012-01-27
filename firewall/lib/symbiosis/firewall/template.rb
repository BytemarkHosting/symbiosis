require 'symbiosis/ipaddr'
require 'symbiosis/firewall/ports'
require 'erb'

module Symbiosis

  module Firewall
    #
    #  This class encapsulates a single firewall (iptables) template 
    #
    class Template

      def self.directories
        @directories ||= ["."]
      end

      #
      # If we specify a template directory, prepend it, unless it is an array,
      # in which case overwrite it.
      #
      def self.directories=(tds)

        case tds
        when String
          @directories = [ tds ] + @directories
        when Array
          @directories = tds
        else
          raise ArgumentError, "#{tds.inspect} is not a string or an array"
        end
      end

      #
      # Return which address families have been set.  Defaults to inet inet6
      #
      def self.address_families
        @address_families ||= %w(inet inet6)
      end

      #
      # Specify which address families the templates can be run for,
      #
      def self.address_families=(afs)
        case afs
          when String
            @address_families = [ afs ]
          when Array
            @address_families = afs
          else
            raise ArgumentError, "#{afs.inspect} is not a string or an array"
        end
        
      end

      #
      # Return a list of suitable iptables commands.
      #
      def self.iptables_cmds
        iptables_cmds = []
        iptables_cmds << "/sbin/iptables"  if self.address_families.include?("inet")
        iptables_cmds << "/sbin/ip6tables" if self.address_families.include?("inet6")
        iptables_cmds
      end

      #
      # Search our template directories for files
      #
      def self.find(files, directories = @directories)
       
        path = nil
        files = [ files ] unless files.is_a?(Array)

        files.compact.each do |file| 
          #
          # Search all the template directories...
          #
          directories.each do |dir|
            path = "#{dir}/#{file}"
            break if File.exists?(path)

            path = nil
          end

          break unless path.nil?
        end

        # uh-oh!  not found it.
        raise ArgumentError, "Could not find any templates called #{files.join(" or ")}." unless path and File.exists?(path)

        return path
      end

      attr_reader :name
      attr_reader :address
      attr_reader :port
      attr_reader :direction
      attr_reader :chain
      attr_reader :template_file

      #
      #  Constructor
      #
      def initialize( template_file )
        #
        # Some defaults..
        #
        @name          = nil
        @address       = nil
        @port          = nil
        @direction     = "incoming"
        @chain         = nil

        @template_file = template_file
      end

      def name=( new_name )
        #
        # Guess the port from the name, if it has not already been set.
        #
        self.port = new_name if self.port.nil?
        @name = new_name
      end
      
      #
      #  Set the source/dest
      #
      def address=( new_address )
        #
        # If we're given an IPAddr, suck it up, otherwise if it is a string,
        # convert it.
        #
        case new_address
          when IPAddr 
            @address = new_address
          when String
            @address = IPAddr.new(new_address)
          else
            raise ArgumentError, "Cannot do much with #{new_address.inspect}"
        end
      end

      #
      # Set the port
      #
      def port=( new_port )
        if new_port.is_a?(Integer)
          @port = new_port
        else    
          @port = Ports.lookup( new_port )
        end
      end
      
      #
      # Set the chain
      #
      def chain=( new_chain )
        @chain= new_chain
      end


      def template_file=(tf)
        raise Errno::ENOENT, tf unless File.exists?(tf)
        @template_file = tf
      end
      
      def direction=(d)
        case d
          when "incoming"
            self.incoming
          when "outgoing"
            self.outgoing
          else
           raise ArgumentError, "Bad direction #{d.inspect}"
        end
      end

      #
      #  Set this rule to work against incoming connections.
      #
      def incoming
        self.chain     = "INPUT" if self.chain.nil?
        @direction = "incoming"
      end

      #
      #  Is this incoming?
      #
      def incoming?
        "incoming" == self.direction
      end

      #
      # Set this rule to work against outgoing connections.
      #
      def outgoing
        self.chain     = "OUTPUT" if self.chain.nil?
        @direction = "outgoing"
      end

      #
      #  Is this an outgoing rule?
      #
      def outgoing?
        "outgoing" == self.direction
      end

      #
      # Two convenience methods to allow us to use chain/src_or_dst for templates.
      #
      
      #
      #  Return the iptables src
      #
      def src
        return "" if self.address.nil?
        "--src #{self.address}"
      end

      alias source src

      #
      #  Return the iptables dst 
      #
      def dst
        return "" if self.address.nil?
        "--dst #{self.address}"
      end

      alias destination dst

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
        self.class.address_families.include?("inet6") and
        (self.address.nil? or (self.address.is_a?(IPAddr) and self.address.ipv6?) )
      end
    
      #
      # Is this an IPv4 rule?
      #
      def ipv4?
        self.class.address_families.include?("inet") and
        (self.address.nil? or (self.address.is_a?(IPAddr) and self.address.ipv4?) )
      end

      #
      # Return the correct iptables command for the protocol
      #
      def iptables_cmds
        #
        # This returns the iptables commands based on the Template address_families param.
        #
        cmds = self.class.iptables_cmds
        cmds.delete("/sbin/iptables") unless self.ipv4?
        cmds.delete("/sbin/ip6tables") unless self.ipv6?
        cmds
      end

      #
      # The meat of the code.  This is designed to return the
      # actual "iptables" command which this rule can be used
      # to generate.
      #
      # TODO: this could be neater.
      #
      def to_s
        template = File.read(self.template_file)
        #
        # Detect if this is a legacy-style rule, or an ERB one. 
        #
        if template =~ /\$(SRC|DEST)/
          #
          # Legacy template.
          #
          lines = template.split("\n")

          if !ipv4? and lines.any?{|l| l =~ /^[^#]*iptables /}
            warn "Disabling IPv4 rules for non-IPv4 addresses in #{self.name}" if $VERBOSE
            lines = lines.collect{|l| l =~ /^[^#]*iptables / ? "# "+l : l }
          end

          if !ipv6? and lines.any?{|l| l =~ /^[^#]*ip6tables /}
            warn "Disabling IPv6 rules for non-IPv6 addresses in #{self.name}" if $VERBOSE
            lines = lines.collect{|l| l =~ /^[^#]*ip6tables / ? "# "+l : l }
          end

          lines = lines.collect{|l| l.gsub("$SRC",src).gsub("$DEST",dst)}

          lines = lines.collect do |l|
            # 
            # Replace SRC and DEST variable
            #
            l = l.gsub("$SRC",src).gsub("$DEST",dst)

            #
            # Check there aren't any more odd variables.
            #
            while l =~ /(\$[A-Z]+)/
              warn "Bad variable #{$1} in #{self.template_file} -- removing!"
              l = l.gsub($1,"")
            end

            #
            # Return the newly mangled line.
            #
            l
          end

          return lines.join("\n") 
        else
          begin
            # Return the interpolated template.
            return ERB.new(template,0,'%>').result(binding)

          rescue NoMethodError,ArgumentError,SyntaxError => err
            # Rescue  
            warn "Caught error in #{template_file}: #{err.to_s}"
            raise err
          end

        end
      end

    end

  end

end
