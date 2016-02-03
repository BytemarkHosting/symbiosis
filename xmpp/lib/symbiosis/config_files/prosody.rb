require 'symbiosis/config_file'
require 'tempfile'

module Symbiosis
  module ConfigFiles
    class Prosody < Symbiosis::ConfigFile

      #
      # Check config with luac.
      #
      def ok?
        return false unless File.executable?("/usr/bin/luac")

        output = []

        config = self.generate_config(self.template)

        tempfile = Tempfile.new(File.basename(self.filename))
        tempfile.puts(config)
        tempfile.close(false)

        IO.popen( "/usr/bin/luac -p #{tempfile.path} 2>&1 ") {|io| output = io.readlines }

        if $?.exitstatus == 0
          tempfile.unlink
          return true
        else
          warn output.collect{|o| "\t"+o}.join.chomp
          File.rename(tempfile.path, tempfile.path+".conf")
          warn "\tTemporary config snippet retained at #{tempfile.path}.conf"
          return false
        end

        true
      end

      #
      # This checks a site has its config file linked into the conf.d
      # directory.  If no filename has been specified, it defaults to
      # self.filename with "conf.avail" transformed to "conf.d".
      #
      # This function returns true if self.filename is symlinked to fn.
      #
      def enabled?(fn = nil)

        fn = self.filename.sub("conf.avail","conf.d") if fn.nil?

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
      # conf.avail changed to conf.d.
      #
      # If the force flag is set to true, then any file in the way is removed
      # first.
      #
      def enable(fn = nil, force = false)
        #
        # Take the filename and and replace available with enabled if no
        # filename is given.
        #
        fn = self.filename.sub("conf.avail","conf.d") if fn.nil?

        #
        # Do nothing if we're already enabled.
        #
        return if self.enabled?(fn)

        #
        # Clobber any files in the way, if the force flag is set.
        #
        if force and File.exist?(fn)
          File.unlink(fn)
        end

        #
        # If the file is still there after disabling, raise an error
        #
        raise Errno::EEXIST, fn if File.exist?(fn)

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
        fn = self.filename.sub("conf.avail","conf.d") if fn.nil?

        #
        # Remove the file, only if it is a symlink to our filename, or if the
        # force flag is set.
        #
        if self.enabled?(fn) or (File.exist?(fn) and force)
          File.unlink(fn)
        end

        #
        # If the file is still there after disabling, raise an error
        #
        raise Errno::EEXIST, fn if File.exist?(fn)

        nil
      end

      #
      # Returns the certificate, key, and bundle configuration lines.
      #
      # This does not have an explicit validation step.  That should be handled
      # elsewhere.
      #
      def ssl_config
        ans = []

        if defined?(@domain) and @domain.is_a?(Symbiosis::Domain) and @domain.ssl_enabled?
          #
          # Here's our cert.
          #
          ans << "certificate = \"#{@domain.ssl_certificate_file}\""

          #
          # Add the separate key unless the key is in the certificate.
          #
          ans << "key = \"#{@domain.ssl_key_file}\""

          #
          # Add a bundle, if needed.
          #
          ans << "cafile = \"#{@domain.ssl_bundle_file}\"" if @domain.ssl_bundle_file

        elsif File.exist?("/etc/ssl/ssl.crt") and File.exist?("/etc/ssl/ssl.key")
          #
          # TODO: this makes absolutely no checks for the certificate validity
          # etc., unlike the @domain functions above.
          #
          ans << "certificate = \"/etc/ssl/ssl.crt\""

          #
          # Add the key and bundle, assuming they exist.
          #
          ans << "key = \"/etc/ssl/ssl.key\""
          ans << "cafile = \"/etc/ssl/ssl.bundle\"" if File.exist?("/etc/ssl/ssl.bundle")
        end

        #
        # If there is no SSL, return an empty string.
        #
        return "" if ans.empty?

        ans.join(";\n")+";\n"
      end

    end

  end

end


