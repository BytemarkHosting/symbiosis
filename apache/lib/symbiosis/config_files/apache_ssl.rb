require 'symbiosis/config_file'
require 'tempfile'

module Symbiosis
  module ConfigFiles
    class ApacheSSL < Symbiosis::ConfigFile

      #
      # Does the SSL site need updating because a file is more
      # recent than the generated Apache site?
      #
      def outdated?

        #
        # creation time of the (previously generated) SSL-site.
        #
        site = File.mtime( self.filename )
  
        #
        #  For each configuration file see if it is more recent
        #
        %w( ssl_bundle_file ssl_key_file ssl_certificate_file ip_file ).any? do |meth|
          file = self.domain.__send__(meth)
          !file.nil? and File.exists?( file ) and File.mtime( file ) > site 
        end
      end

      #
      # Test the file using Apache and a temporary file.
      #
      def ok?
        return false unless File.executable?("/usr/sbin/apache2")

        output = []

        config = self.generate_config(self.template)

        tempfile = Tempfile.new($0)

        tempfile.puts(config)

        IO.popen( "/usr/sbin/apache2 -C 'UseCanonicalName off' -C 'Include /etc/apache2/mods-enabled/*.load' -C 'Include /etc/apache2/mods-enabled/*.conf' -f #{tempfile.path} -t 2>&1 ") {|io| output = io.readlines }

        warn output.collect{|o| "\t"+o}.join unless "Syntax OK" == output.last.chomp or $VERBOSE

        "Syntax OK" == output.last.chomp
      end


      #
      # This checks a site has its config file linked into the sites-enabled
      # directory.
      #
      def enabled?(fn = nil)

        fn = self.filename.gsub("sites-available","sites-enabled")) if fn.nil?
        
        #
        # Make sure the file exists, and that it is a symlink pointing to our
        # config file
        #
        if File.symlink?(fn) and File.expand_path(fn.readlink) == self.filename
          return true
        end

        #
        # If a file with the correct name exists, raise an EEXIST error
        #
        raise Errno::EEXIST, fn if File.exists?(fn)

        #
        # FIXME: should probably check at this point to see if any files point
        # back to the config, or if any file contains the configuration for
        # this domain.
        #

        #
        # Otherwise return false
        #
        false
      end

    end
  end
end


