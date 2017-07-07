require 'digest/md5'
require 'erubis'
require 'erubis/engine/enhanced'
require 'tempfile'
require 'symbiosis/domain'
require 'diffy'

module Symbiosis

  #
  # This class is used to make configuration files easier to handle.
  #
  # The idea is that we write an MD5 sum to the file in a parseable way, and then
  # check that to see if it has changed, or not.
  #
  # This class is a base that should be absorbed into child classes.
  #
  class ConfigFile

    #
    # This class only exists to get around the annoying "@prefixrexp" not
    # defined warnings due to missing bits in the actual erubis code.
    #
    class Eruby < ::Erubis::Eruby
      include Erubis::PercentLineEnhancer

      def init_generator(properties={})
        super
        @prefixchar = properties[:prefixchar] || '%'
        @prefixrexp = properties[:prefixrexp] || Regexp.compile("^#{@prefixchar}(.*?\\r?\\n)")
      end

    end

    attr_reader :comment_char, :filename, :template, :domain

    #
    # Sets up a configuration file 'filename'.  The comment character
    # 'comment_char' is used before the MD5 sum, and is assumed to be a hash.
    #
    def initialize(filename, comment_char='#')
      @filename = filename
      @comment_char = comment_char
      @contents = nil
      @template = nil
      @domain = nil
      @managed = nil
    end

    #
    # Allow the ERB interpreter to be set by any subclass. This allows
    # automatic escaping to be set up, for example.
    #
    def self.erb=(klazz)
      raise ArgumentError unless klazz.is_a?(Class)
      raise ArgumentError, "ERB class #{klazz.inspect} is not descended from Erubis::Eruby" unless klazz.ancestors.include?(Erubis::Eruby)
      @erb = klazz
    end

    #
    # This returns the ERB interpreter class.
    #
    def self.erb
      #
      # We default to the PercentLineEruby interpreter, since this allows lines
      # to start with %.
      #
      @erb ||= Eruby
    end

    #
    # Set the domain -- potentially used in tests later, or in the template.
    # Must be a Symbiosis::Domain.
    #
    def domain=(d)
      raise "The domain must be a Symbiosis::Domain not a #{d.class}" unless d.is_a?(Symbiosis::Domain)
      @domain = d
    end

    #
    # Set the template filename.  Raises Errno::ENOENT if the file does not exist.
    #
    def template=(f)
      raise Errno::ENOENT,f unless File.exist?(f)

      @template = f
    end

    #
    # Template the configuration.  Adds " Checksum MD5 " and the MD5 hash of
    # the preceding configuration, prepended by comment_char and to the end of
    # the generated config.
    #
    def generate_config( templ = self.template )
      #
      # Read the template file.
      #
      content = File.open( templ, "r" ).read()

      #
      # Create a template object, and add a newline for good measure.
      #
      config = self.class.erb.new( content ).result( binding )

      #
      # Return our template + MD5.
      #
      return config + [self.comment_char,"Checksum MD5",Digest::MD5.new.hexdigest(config)].join(" ")+"\n"
    end

    #
    # Writes the configuration specified by config to the filename specified in
    # the constructor.  The opts has takes options for the
    # Symbiosis::Utils#safe_open method.
    #
    def write(config = self.generate_config, opts = {})
      Symbiosis::Utils.safe_open(self.filename,"a+", opts) do |fn|
        fn.truncate(0)
        fn.write(config)
      end

      self.filename
    end

    #
    # Return a diff of the new configuration comapred with the existing one.
    # The format option can take on of Diff::Diff.to_s() format options,
    # currently :text, :color, :html, and :html_simple. Defaults to :html.  A
    # different configuraion template can be specified in the second option.
    #
    def diff(format = nil, templ = self.template)
      config = generate_config(tmpl)

      tempfile = Tempfile.new(File.basename(filename))
      tempfile.puts(config)
      tempfile.flush

      fn = ( File.exists?(self.filename) ? self.filename : '/dev/null' )

      Diffy::Diff.new(fn, tempfile.path, source: 'files', include_diff_info: true).to_s(format)
    end

    #
    # See if the generated config is OK.  This method always returns true, and
    # thus should be overwritten in any child class.
    #
    def ok?
      true
    end

    # alias ok? test

    #
    # Does the configuration need updating.  It tests to see if the MD5 of the
    # current file, and a new configuration based on templ match.
    #
    # If no checksum is found in the original file, it returns true.
    #
    def outdated?(templ = self.template)
      #
      # The checksum we're going to look at.
      #
      checksum = nil

      #
      # First read the filename, and then generate the snippet.
      #
      [File.readlines(self.filename), self.generate_config(template).split($/)].each do |snippet|
        #
        # Make sure we don't barf on empty files/templates -- these definitely
        # do not contain checksums.
        #
        break unless snippet.last.is_a?(String)

        #
        # We expect the checksum to be the last line of the file
        #
        if snippet.last.chomp =~ /^#{self.comment_char} Checksum MD5 ([a-f0-9]{32,32})$/
          #
          # OK we've found the checksum
          #
          if checksum.nil?
            checksum = $1
          else
            return checksum != $1
          end

        end

        #
        # The checksum should not be nil now.
        #
        break if checksum.nil?

      end

      #
      # If no checksum can be found, assume it is out of date.
      #
      return true
    end

    #
    # Test to see if the config file exists
    #
    def exists?
      File.exist?(filename)
    end

    #
    # This tests to see if the configuration has changed.  First it checks to
    # see if there is an MD5 sum in the file (defined by filename), and if so,
    # it checks to see if that MD5 sum is correct for that file.  If the MD5
    # sums match, then false is returned, otherwise true.
    #
    # If no MD5 sum is found, the phrase " DO NOT EDIT THIS FILE - CHANGES WILL
    # BE OVERWRITTEN", prepended by the comment_char is looked for.  If that
    # phrase is found, then false is returned.
    #
    # If neither an MD5 or a warning could be found, then the file is assumed
    # to have changed, so the method returns true.
    #
    def changed?
      #
      # Read the snippet
      #
      snippet = File.readlines(self.filename)

      #
      # Set the managed parameter
      #
      @managed = false

      #
      # We expect the checksum to be the last line of the file
      #
      if snippet.last.is_a?(String) and snippet.last.chomp =~ /^#{self.comment_char} Checksum MD5 ([a-f0-9]{32,32})$/
        #
        # OK we've found the checksum
        #
        supposed_checksum = $1

        #
        # This file must have been managed at some point
        #
        @managed = true

        #
        # Pop off the last line, as this isn't part of the checksum
        #
        snippet.pop

        #
        # And compare to the calculated checksum of the rest of the snippet
        #
        return Digest::MD5.new.hexdigest(snippet.join) != supposed_checksum

      #
      # If the file has a big warning in it, we ignore changes
      #
      elsif snippet.any?{|l| l.is_a?(String) and self.comment_char+" DO NOT EDIT THIS FILE - CHANGES WILL BE OVERWRITTEN" == l.chomp}
        #
        # This file must have been managed at some point
        #
        @managed = true

        #
        # So return false
        #
        return false

      end

      #
      # Assume the file has been edited.
      #
      puts "\tCould not find checksum or big warning." if $VERBOSE

      true
    end

    #
    # This returns true if Symbiosis has managed this file at some point.
    #
    def managed?
      #
      # This uses the same checks as #changed?, so use that code instead.
      #
      self.changed?

      @managed
    end

  end

  #
  # This module contains all the various ConfigFile child classes.
  #
  module ConfigFiles

  end

end
