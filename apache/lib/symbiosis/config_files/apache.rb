require 'symbiosis/config_file'
require 'tempfile'

module Symbiosis
  module ConfigFiles
    class Apache < Symbiosis::ConfigFile

      #
      # Tests the file using Apache and a temporary file.  Returns true if
      # apache2 deems the snippet OK.
      #
      def ok?
        return false unless File.executable?("/usr/sbin/apache2")

        output = []

        config = self.generate_config(self.template)

        tempfile = Tempfile.new(File.basename(self.filename))
        tempfile.puts(config)
        tempfile.close(false)

        IO.popen( "/usr/sbin/apache2 -C 'UseCanonicalName off' -C 'Include /etc/apache2/mods-enabled/*.load' -C 'Include /etc/apache2/mods-enabled/*.conf' -f #{tempfile.path} -t 2>&1 ") {|io| output = io.readlines }

        if "Syntax OK" == output.last.chomp
          warn output.collect{|o| "\t"+o}.join.chomp if $VERBOSE
          tempfile.unlink
          return true
        else
          warn output.collect{|o| "\t"+o}.join.chomp
          File.rename(tempfile.path, tempfile.path+".conf")
          warn "\tTemporary config snippet retained at #{tempfile.path}.conf"
          return false
        end
      end


      #
      # This checks a site has its config file linked into the sites-enabled
      # directory.  If no filename has been specified, it defaults to
      # self.filename with "sites-available" transformed to "sites-enabled".
      #
      # This function returns true if self.filename is symlinked to fn.
      #
      def enabled?(fn = nil)

        fn = self.filename.sub("sites-available","sites-enabled") if fn.nil?

        #
        # Make sure the file exists, and that it is a symlink pointing to our
        # config file
        #
        if File.symlink?(fn) 
          ln = File.readlink(fn)

          unless ln =~ /^\//
            ln = File.join(File.dirname(fn),ln)
          end

          return File.expand_path(ln) == self.filename
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

      #
      # This enables a site by symlinking the self.filename to fn.
      #
      # If fn is not specified, then self.filename is used, with
      # sites-available changed to sites-enabled.
      #
      # If the force flag is set to true, then any file in the way is removed
      # first.
      #
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

      #
      # This disables a site whose configuration is contained in fn.  This
      # function makes sure that the site is enabled, before disabling it.
      # 
      # 
      #
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

      #
      # Returns an array of Symbiosis::IPAddr objects, one for each IP
      # available for this domain, if defined, or the system's primary IPv4 and
      # IPv6 addresses.
      #
      def available_ips
        if defined? @domain and @domain.is_a?(Symbiosis::Domain)
          @domain.ips
        else
          [Symbiosis::Host.primary_ipv4, Symbiosis::Host.primary_ipv6].compact
        end
      end

      #
      # Return all the IPs as apache-compatible strings for use in templates.
      #
      def ips
        self.available_ips.collect do |ip|
          if ip.ipv6?
            "["+ip.to_s+"]"
          else
            ip.to_s
          end
        end
      end

      #
      # Return just the first IP for use in templates.
      #
      def ip
        ip = self.available_ips.first
        warn "\tUsing one IP (#{ip}) where the domain has more than one configured!" if self.available_ips.length > 1 and $VERBOSE
        if ip.ipv6?
          "["+ip.to_s+"]"
        else
          ip.to_s
        end
      end

      #
      # Return the domain config directory.
      #
      # If no domain has been defined, nil is returned.
      #
      def domain_directory
        if defined?(@domain) and @domain.is_a?(Symbiosis::Domain) 
          @domain.directory
        else
          nil
        end
      end

      #
      # Returns the certificate, key, and bundle configuration lines.
      #
      def ssl_config
        ans = []
        if defined?(@domain) and @domain.is_a?(Symbiosis::Domain) 
          unless @domain.ssl_certificate_file and @domain.ssl_key_file
            ans << "SSLCertificateFile #{@domain.ssl_certificate_file}"
            #
            # Add the separate key unless the key is in the certificate. 
            #
            ans << "SSLCertificateKeyFile #{@domain.ssl_key_file}" unless @domain.ssl_certificate_file == @domain.ssl_key_file
            #
            # Add a bundle, if needed.
            #
            ans << "SSLCertificateChainFile #{@domain.ssl_bundle_file}" if @domain.ssl_bundle_file
          end
        elsif File.exists?("/etc/ssl/ssl.crt")
          #
          # TODO: this makes absolutely no checks for the certificate validity
          # etc., unlike the @domain functions above.
          #
          ans << "SSLCertificateFile /etc/ssl/ssl.crt"
          #
          # Add the key and bundle, assuming they exist.
          #
          ans << "SSLCertificateKeyFile /etc/ssl/ssl.key" if File.exists?("/etc/ssl/ssl.key")
          ans << "SSLCertificateChainFile /etc/ssl/ssl.bundle" if File.exists?("/etc/ssl/ssl.bundle")
        end

        ans.join("\n        ")
      end

      #
      # Checks to see if a domain has mandatory ssl.
      #
      # If no domain is set, then this returns false.
      #
      def mandatory_ssl?
        if defined?(@domain) and @domain.is_a?(Symbiosis::Domain) 
          @domain.ssl_mandatory?
        else
          false
        end
      end

    end
  end
end


