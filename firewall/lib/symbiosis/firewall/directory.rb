require 'symbiosis/firewall/template'
require 'symbiosis/domain'
require 'resolv-replace'

module Symbiosis
  module Firewall

    #
    # This is a superclass that is inherited by
    # Symbiosis::Firewall::IPListDirectory and
    # Symbiosis::Firewall::TemplateDirectory.  It represents a directory, like
    # incoming.d, blacklist.d, etc.
    #
    class Directory 

      attr_reader :direction, :chain, :path, :default

      #
      # path::      directory where the rules are
      # direction:: either _incoming_ or _outgoing_
      # chain::     Specify the rules go in the chain of this name.  This can
      #             be nil, in which case, INPUT or OUTPUT is chosen based on
      #             direction.
      #
      def initialize(path, direction, chain = nil)
        raise Errno::ENOENT,path unless File.directory?(path)
        @path = path

        raise ArgumentError, "direction must be either incoming or outgoing" unless %w(incoming outgoing).include?(direction.to_s)
        @direction = direction

        @chain = chain
        @default = "accept"
      end

      #
      # Set the default template name.  Defaults to "accept".
      #
      def default=(d)
        @default = d
      end

      #
      # Reads the directory, and returns an array of templates and hostames,
      # i.e. 
      #
      #  [
      #    [template, hostnames],
      #    [another template, other hostnames]
      #  ]
      #
      def read
        do_read
      end

      #
      # Return a string that is to be inserted into the firewall script for
      # execution.
      #
      def to_s
        #
        # This is an array of rules that will be written to the script
        #
        rules = []

        rules << "#"*72
        rules << "#"
        rules << "# Rules from #{path}"
        rules << "#"
        rules << "#"*72

        #
        # Read the rules, and generate.
        #
        do_read.each do |template, hostnames|
          rules += do_generate_rules( template, hostnames )
        end

        return rules.join("\n")
      end

      private

      #
      # Stub method.  This should return an array of ready-to-go templates.
      #
      def do_read( directory )
        Array.new
      end

      #
      # Searches the template directories to find the template.
      #
      def do_find_template(template, ext = self.direction)
        #
        # Use the method defined in Template.
        #
        Template.find("#{template}.#{ext}")
      end
 

      #
      # This applies the template, and catches any error in its generation
      #
      def do_generate_rules(template, hostnames)
        rules = []
        addresses = []

        #
        # resolve addresses
        #
        hostnames.each do |hostname|
          addresses += do_resolve_name(hostname)
        end

        #
        # Now, for each address create a template and add it to our rules.
        #
        addresses.uniq.each do |address|
          begin
            #
            # Create a new rule
            #
            template.address = address unless address.nil?
            rules << template.to_s
          rescue ArgumentError => err
            #
            # Catch any error and display neatly.
            #
            msg = "Ignoring #{self.direction} rule #{template.name} #{address.nil? ? "" : "to #{address.inspect} "}because #{err.to_s}"
            warn msg
            rules << "# #{msg}"
          end
        end

        return rules
      end

      #
      # Resolve hostnames to A and AAAA records.
      #
      # The name is a string, and can be a hostname or an IP address.  A
      # hostname will get resolved to a set of IP addresses, based on the A or
      # AAAA records available.
      #
      def do_resolve_name(name)
        ips = []

        begin
          case name
            when IPAddr
              ips << name
            when String
              ips << IPAddr.new(name)
            when NilClass
              ips << name
            else
              warn "#{name.inspect} could not be resolved because it is a #{name.class}." if $VERBOSE
          end
        rescue ArgumentError
          %w(A AAAA).each do |type|
            begin
              Resolv::DNS.open do |dns|
                #
                # This works with CNAME records too, depending on what the
                # resolver gives us.
                #
                dns.getresources(name, Resolv::DNS::Resource::IN.const_get(type)).each do |a|
                  #
                  # Convert to IPAddr straight away, ignoring errors.
                  #
                  begin
                    ips << IPAddr.new(a.address.to_s)
                  rescue ArgumentError
                    warn "#{type} record for #{name} returned duff IP #{a.address.to_s.inspect}." if $VERBOSE
                  end
                end
              end
            rescue Resolv::ResolvError, Resolv::ResolvTimeout => e
              warn "#{name} could not be resolved because #{e.message}." if $VERBOSE
            end
          end
        end

        ips
      end

    end


    #
    # This class describes a directory containing rule names and ports.
    #
    # For example the following directory tree will allow ports 22, 33, and
    # those defined by the "dns" template, in that order.
    #
    #  .
    #  |--- 10-22
    #  |--- 20-33
    #  \--- 30-dns
    #
    # The order in which the rules are generated is determined by filename.
    # The part of the filename up to the first dash is used for this, and it
    # must be numeric.
    #
    # Each file can be empty, or contain a list of addresses or hostnames.  In
    # the case of an emtpy file, no restrictions are placed on which IP can
    # access that port.  If hostnames or addresses are specified, then only
    # those hosts can access that port.  If the addresses are IPv4, then
    # they're added using iptables.  If they are IPv6, they are added using
    # ip6tables.
    #
    # *NB* that hostnames are resolved using A and AAAA lookups when the
    # firewall is run.
    #
    class TemplateDirectory < Directory

      private

      #
      #  Read from an incoming/outgoing directory
      #
      def do_read
        #
        # Results is an array of arrays:
        #
        #  [
        #    [template1, [ipaddress1, ipaddress2]],
        #    [template2, [ipaddress3, ipaddress4]],
        #  ]
        #
        # and so on.
        #
        results = Array.new

        default_template_path = do_find_template(self.default)

        Dir.entries( self.path ).sort.each do |entry|

          #
          # Ignore files that are left over by from dpkg
          #
          next if entry =~ /\.dpkg-[a-z0-9]+$/

          next unless entry =~ /^([0-9]*)-(.*)$/
          name = $2

          #
          # Try to find a template.  If none is found use the default template,
          # but only if the service/port can be found.  I.e. don't default to
          # "accept".
          #
          begin
            template_path = do_find_template( name )
          rescue ArgumentError => err
            if name == self.default or Ports.lookup(name) != nil
              template_path = default_template_path 
            else
              warn "Skipping #{entry} -- #{err.to_s}"
              next
            end
          end
          
          template = Template.new( template_path )
          template.name = name
          template.direction = self.direction
          template.chain = self.chain unless self.chain.nil?

          #
          # File.readlines always returns an array, one element per line, even
          # for dos-style files.  Reject hostnames that start with "#" or are
          # empty strings.
          #
          hostnames = []
          File.readlines( File.join( self.path, entry ) ).each do |l|
            hostname = l.chomp.strip
            next if hostname.empty? 
            next if hostname =~ /^#/

            hostnames << hostname
          end

          #
          # Add a dummy address of nil if there are no hostnames in the list
          #
          hostnames << nil if hostnames.empty?
          
          #
          # Append our result
          #
          results << [template, hostnames] 
        end

        #
        #  Return the names.
        #
        results
      end

    end

    #
    # This class allows a directory containing IP addresses to be used
    # to construct either a whitelist or a blacklist of the IP addresses
    # which are in that directory.
    #
    # For example the following directory tree will blacklist all incoming
    # connections from the IP addresses 1.2.3.4, 1.4.4.4, and 10.20.30.40:
    #
    #  .
    #  |--- 10.20.30.40
    #  |--- 1.2.3.4
    #  \--- 1.4.4.4
    #
    # If the name looks like an IP address and is of the form
    #
    #  1.2.3.4|24
    #
    # or 
    #
    #  2001:dead:beef:cafe::1|64
    #
    # then these would be mangled to become 1.2.3.4/24 or
    # 2001:dead:beef:cafe::1/64 respectively, before being transformed into
    # an IP address.
    #
    # Each file can contain a list of ports/services/templates, or the word
    # "all", or nothing at all.
    #
    #
    class IPListDirectory < Directory

      private

      #
      # Returns an array like
      #
      #  [
      #    [template, [ address1, address2 ]]
      #  ]
      #
      def do_read

        templates = []

        #
        # A hash of arrays
        #
        port_hostnames = Hash.new{|i,j| i[j] = []}
        
        #
        # We only ever use the default template.
        #
        default_template_path = do_find_template( self.default )

        #
        #  Read the contents of the directory
        #
        Dir.entries( self.path ).each do |file|
          #
          #  Skip "dotfiles".
          #
          next if ( file =~ /^\./ )

          #
          #  Here we need to strip the optional ".auto" suffix.
          #
          hostname = File.basename(file,".auto").downcase
          
          #
          # Cope with ranges by unmangling the CIDR notation.
          #
          if hostname =~ /^([0-9a-f\.:]+)\|([0-9]+)$/
           hostname = [$1, $2].join("/")
          end

          #
          # Now see if the file contains any lines for ports Tidy port list,
          # removing empty lines, and stripping out white space.
          #
          ports = []
          File.readlines( File.join( self.path, file ) ).each do |l|
            port = l.chomp.strip
            next if port.empty?
            next unless port =~ /^([a-z0-9]+|all)$/

            ports << port
          end
         
          #
          # Now we have our sanitised list, if the list is empty, assume all
          # ports.  If nothing is specified, or one of the lines is "all", then
          # the array can just contain "nil", which means all ports.
          #
          if ports.empty? or ports.any?{|port| "all" == port}
            ports = [nil] 
          end

          #
          # Save each port/address combo.
          #
          ports.each do |port|
            port_hostnames[port] << hostname
          end
        end

        #
        # Now translate our ports into templates.
        #
        port_hostnames.each do |port, hostnames|
          template = Template.new( default_template_path )
          template.name = self.default
          template.direction = self.direction
          template.port = port unless port.nil? 
          template.chain = self.chain unless self.chain.nil?
          templates << [template, hostnames]
        end

        return templates
      end

    end

  end

end
