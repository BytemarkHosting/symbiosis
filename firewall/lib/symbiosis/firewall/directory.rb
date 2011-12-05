require 'symbiosis/firewall/template'
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
        do_read.each do |template, addresses|
          rules += do_generate_rules( template, addresses )
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
        Template.find(["#{template}.#{ext}", "#{self.default}.#{ext}"])
      end
 

      #
      # This applies the template, and catches any error in its generation
      #
      def do_generate_rules(template, addresses)
        rules = []

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
            msg = "Ignoring #{self.direction} rule #{template} #{address.nil? ? "" : "to #{address.inspect} "}because #{err.to_s}"
            warn msg
            rules << "# #{msg}"
          end
        end

        return rules
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

        Dir.entries( self.path ).sort.each do |entry|

          next unless entry =~ /^([0-9]*)-(.*)$/
          name = $2

          template_path = do_find_template( name )
          template = Template.new( template_path )
          template.name = name
          template.direction = self.direction
          template.chain = self.chain unless self.chain.nil?

          #
          # File.readlines always returns an array, one element per line, even for dos-style files.
          #
          addresses = File.readlines( File.join( self.path, entry ) ).collect{|l| l.chomp}

          #
          # Add a dummy address of nil if there are no addresses in the list
          #
          addresses << nil if addresses.empty?
          
          #
          # Append our result
          #
          results << [template, addresses] 
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
    # 0 directories, 3 files
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
        port_addresses = Hash.new{|i,j| i[j] = []}

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
          ip = File.basename(file,".auto") 

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
            port_addresses[port] << ip
          end
        end

        #
        # Now translate our ports into templates.
        #
        port_addresses.each do |port, addresses|
          template_path = do_find_template( self.default )
          template = Template.new( template_path )
          template.name = self.default
          template.direction = self.direction
          template.port = port unless port.nil? 
          template.chain = self.chain unless self.chain.nil?
          templates << [template, addresses]
        end

        return templates
      end

    end

  end

end
