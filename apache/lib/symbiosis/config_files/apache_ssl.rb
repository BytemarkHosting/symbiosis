require 'symbiosis/config_file'
require 'tempfile'

module Symbiosis
  module ConfigFiles
    class ApacheSSL < Symbiosis::ConfigFile

      #
      # Test the file using Apache and a temporary file.
      #
      def ok?
        return false unless File.executable?("/usr/sbin/apache2")

        output = []

        config = self.generate_config(self.template)

        tempfile = Tempfile.new(self.domain.name)
        tempfile.puts(config)
        tempfile.close(false)

        IO.popen( "/usr/sbin/apache2 -C 'UseCanonicalName off' -C 'Include /etc/apache2/mods-enabled/*.load' -C 'Include /etc/apache2/mods-enabled/*.conf' -f #{tempfile.path} -t 2>&1 ") {|io| output = io.readlines }

        if "Syntax OK" == output.last.chomp
          warn output.collect{|o| "\t"+o}.join if $VERBOSE
          tempfile.unlink
          return true
        else
          warn output.collect{|o| "\t"+o}.join
          File.rename(tempfile.path, tempfile.path+".conf")
          warn "\tTemporary config snippet retained at #{tempfile.path}.conf"
          return false
        end
      end


      #
      # This checks a site has its config file linked into the sites-enabled
      # directory.
      #
      def enabled?(fn = nil)

        fn = self.filename.sub("sites-available","sites-enabled") if fn.nil?

        #
        # Make sure the file exists, and that it is a symlink pointing to our
        # config file
        #
        if File.symlink?(fn) and File.expand_path(File.readlink(fn)) == self.filename
          return true
        end

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

      def enable(fn = nil, force = false)
        #
        # Take the filename and and replace available with enabled if no
        # filename is given.
        #
        fn = self.filename.sub("sites-available","sites-enabled") if fn.nil?

        #
        # Do nothing if we're already enabled.
        #
        return if self.enabled?(fn)

        #
        # Clobber any files in the way, if the force flag is set.
        #
        if force and File.exists?(fn)
          File.unlink(fn)
        end

        #
        # If the file is still there after disabling, raise an error
        #
        raise Errno::EEXIST, fn if File.exists?(fn)

        #
        # Symlink away!
        #
        File.symlink(self.filename, fn)
        
        nil
      end

      def disable(fn = nil, force = false)
        #
        # Take the filename and and replace available with enabled if no
        # filename is given.
        #
        fn = self.filename.sub("sites-available","sites-enabled") if fn.nil?

        #
        # Remove the file, only if it is a symlink to our filename, or if the
        # force flag is set.
        #
        if self.enabled?(fn) or (File.exists?(fn) and force)
          File.unlink(fn)
        end

        #
        # If the file is still there after disabling, raise an error
        #
        raise Errno::EEXIST, fn if File.exists?(fn)

        nil
      end

      ###################################################
      #
      # The following methods are used in the template.
      #

      #
      # Return all the IPs as apache-compatible strings.
      #
      def ips
        @domain.ips.collect do |ip|
          if ip.ipv6?
            "["+ip.to_s+"]"
          else
            ip.to_s
          end
        end
      end

      #
      # Return just the first IP.
      #
      def ip
        ip = @domain.ips.first
        warn "\tUsing one IP (#{ip}) where the domain has more than one configured!" if @domain.ips.length > 1 and $VERBOSE
        if ip.ipv6?
          "["+ip.to_s+"]"
        else
          ip.to_s
        end
      end

      #
      # Return the domain config directory.
      #
      def domain_directory
        @domain.config_dir
      end

      #
      # Returns the certificate (+key) snippet 
      #
      def certificate
        return nil unless @domain.ssl_certificate_file and @domain.ssl_key_file

        if @domain.ssl_certificate_file == @domain.ssl_key_file
          "SSLCertificateFile #{@domain.ssl_certificate_file}"
        else
          "SSLCertificateFile #{@domain.ssl_certificate_file}\n\tSSLCertificateKeyFile #{@domain.ssl_key_file}"
        end
      end

      #
      # Returns the bundle filename + the apache directive
      #
      def bundle
        return "" unless @domain.ssl_bundle_file
        
        "SSLCertificateChainFile "+@domain.ssl_bundle_file
      end

      def mandatory_ssl?
        @domain.ssl_mandatory?
      end

    end
  end
end


