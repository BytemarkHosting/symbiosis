require 'symbiosis/firewall/template'
require 'resolv-replace'

#
# A directory, like incoming.d, blacklist.d, local.d.
#
module Symbiosis
  module Firewall
    class Directory 

      attr_reader :direction, :chain, :path, :default

      #
      #  Constructor
      #
      #   * path -> directory where the rules are
      #   * direction -> incoming or outgoing
      #   * chain -> Specify the rules go in the chain of this name.  This can
      #              be nil, in which case, INPUT or OUTPUT is chosen based on
      #              direction.
      #
      def initialize(path, direction, chain = nil)
        raise Errno::ENOENT,path unless File.directory?(path)
        @path = path
        @direction = direction
        @chain = chain
        @default = "accept"
      end

      def default=(d)
        @default = d
      end

      def read
        do_read
      end

      #
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
        addresses.each do |address|
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

        ips.uniq
      end

    end


    #
    #
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
          # File.readlines always returns an array, one element per line, even for dos-style files.
          #
          hostnames = File.readlines( File.join( self.path, entry ) ).collect{|l| l.chomp.strip}

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
    # .
    # |--- 10.20.30.40
    # |---  1.2.3.4
    # \--   1.4.4.4
    #
    # If the name looks like an IP address and is of the form
    #
    #  1.2.3.4-24
    #
    # or 
    #
    #  2001:dead:beef:cafe::1-64
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
          # Now see if the file contains any lines for ports
          #
          ports = File.readlines(File.join(self.path, file))

          #
          # Tidy port list, removing empty lines, and stripping out white
          # space.
          #
          ports = ports.collect do |port|
            port = port.chomp.strip
            if port.empty?
              nil
            else
              port
            end
          end.compact
         
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
