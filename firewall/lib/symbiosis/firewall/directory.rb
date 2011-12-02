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

        template_path = do_find_template( self.default )
        template = Template.new( template_path )
        template.name = self.default
        template.direction = self.direction
        template.chain = self.chain unless self.chain.nil?

        addresses = []
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
          file = File.basename(file,".auto") 

          #
          #  Save it away.
          #
          addresses << file
        end

        return [[template, addresses]]
      end

    end

  end

end
