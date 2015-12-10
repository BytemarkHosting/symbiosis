require 'symbiosis/domain'
require 'symbiosis/ssl'
require 'openssl'
require 'erb'

module Symbiosis

  class Domain

    #
    # Returns true if SSL has been enabled.  SSL is enabled if there is a
    # matching key and certificate found using ssl_find_matching_certificate_and_key.
    #
    def ssl_enabled?
      self.ssl_x509_certificate and self.ssl_key
    end

    #
    # Do we redirect to the SSL only version of this site?
    #
    def ssl_mandatory?
      get_param("ssl-only", self.config_dir)
    end

    #
    # Searches for the domain's SSL certificate using
    # ssl_find_matching_certificate_and_key, and returns the certificate's filename, or
    # nil if nothing could be found.
    #
    def ssl_x509_certificate_file
      @ssl_x509_certificate_file ||= nil

      if @ssl_x509_certificate_file.nil?
        @ssl_x509_certificate_file, @ssl_key_file = self.ssl_find_matching_certificate_and_key
      end

      @ssl_x509_certificate_file
    end

    alias ssl_certificate_file ssl_x509_certificate_file

    #
    # Sets the domains SSL certificate filename.
    #
    def ssl_x509_certificate_file=(f)
      @ssl_x509_certificate_file = f
    end

    alias ssl_certificate_file= ssl_x509_certificate_file=

    #
    # Returns the X509 certificate object
    #
    def ssl_x509_certificate
      if !self.ssl_x509_certificate_file.nil?
        OpenSSL::X509::Certificate.new(File.read(self.ssl_x509_certificate_file))
      else
        nil
      end
    end

    #
    # Searches for the domain's SSL key using
    # ssl_find_matching_certificate_and_key, and returns the key's filename, or
    # nil if nothing could be found.
    #
    def ssl_key_file
      @ssl_key_file ||= nil

      if @ssl_key_file.nil?
        @ssl_x509_certificate_file, @ssl_key_file = self.ssl_find_matching_certificate_and_key
      end

      @ssl_key_file
    end

    #
    # Sets the domains's SSL key filename.
    #
    def ssl_key_file=(f)
      @ssl_key_file = f
    end

    #
    # Returns the domains SSL key as an OpenSSL::PKey::RSA object, or nil if no
    # key file could be found.
    #
    def ssl_key
      unless self.ssl_key_file.nil?
        OpenSSL::PKey::RSA.new(File.read(self.ssl_key_file))
      else
        nil
      end
    end

    #
    # Returns the certificate chain filename, if one exists, or one has been
    # set, or nil if nothing could be found.
    #
    def ssl_certificate_chain_file(dir = self.config_dir)
      if get_param("ssl.bundle", dir)
        File.join( dir,"ssl.bundle" )
      else
        nil
      end
    end

    alias ssl_bundle_file ssl_certificate_chain_file

    #
    # Add a path with extra SSL certs (for testing).
    #
    def ssl_add_ca_path(path)
      @ssl_ca_paths ||= []

      @ssl_ca_paths << path if File.directory?(path)
    end

    #
    # Sets up and returns a new OpenSSL::X509::Store.
    #
    # If any CA paths have been set using ssl_add_ca_path, then these are added to the store.
    #
    # If ssl_certificate_chain_file has been set, then this is added to the store.
    #
    # This is regenerated on every call.
    #
    def ssl_certificate_store(dir = self.config_dir)
      @ssl_ca_paths ||= []

      certificate_store = OpenSSL::X509::Store.new
      certificate_store.set_default_paths

      @ssl_ca_paths.each{|path| certificate_store.add_path(path)}
      certificate_store.add_file(self.ssl_certificate_chain_file(dir)) unless self.ssl_certificate_chain_file(dir).nil?
      certificate_store
    end

    #
    # Return the available certificate/key files for a domain.  It will check
    # files with the following extensions for both keys and certificates.
    #  * combined
    #  * key
    #  * crt
    #  * pem
    #
    # It will return an array of certificate and key filenames that could be
    # read and parsed successfully by OpenSSL.  The array has to sub-arrays,
    # the first being certificate filenames, the second key filenames, i.e.
    # <code>[[certificates] , [keys]]</code>.  If a file contains both a
    # certificate and key, it will appear in both arrays.
    #
    def ssl_available_files(dir = self.config_dir)
      certificates = []
      key_files = []

      #
      # Try a number of permutations
      #
      %w(combined key crt cert pem).each do |ext|
        #
        # See if the file exists.
        #
        contents = get_param("ssl.#{ext}", dir)

        #
        # If it doesn't exist/is unreadble, return nil.
        #
        next unless contents.is_a?(String)

        this_fn = File.join(dir, "ssl.#{ext}")

        this_cert = nil
        this_key = nil

        #
        # Check the certificate
        #
        begin
          this_cert = OpenSSL::X509::Certificate.new(contents)
        rescue OpenSSL::OpenSSLError
          #
          # This means the file did not contain a cert, or the cert it contains
          # is unreadable.
          #
          this_cert = nil
        end

        #
        # Check to see if the file contains a key.
        #
        begin
          this_key = OpenSSL::PKey::RSA.new(contents)
        rescue OpenSSL::OpenSSLError
          #
          # This means the file did not contain a key, or the key it contains
          # is unreadable.
          #
          this_key = nil
        end

        #
        # Finally, if we have a key and certificate in one file, check they
        # match, otherwise reject.
        #
        if this_key and this_cert and this_cert.check_private_key(this_key)
          certificates << [this_fn, this_cert]
          key_files << this_fn
        elsif this_key and !this_cert
          key_files << this_fn
        elsif this_cert and !this_key
          certificates << [this_fn, this_cert]
        end
      end

      #
      # Order certificates by time to expiry, penalising any that are
      # before their start time or after their expiry time.
      #
      now = Time.now
      certificate_files = certificates.sort_by { |fn, cert|
        score = cert.not_after.to_i
        score -= cert.not_before.to_i if cert.not_before > now
        score -= now.to_i if now > cert.not_after
        -score
      }.map { |fn, cert| fn }

      [certificate_files, key_files]
    end

    #
    # This returns an array of files for the domain that contain valid certificates.
    #
    def ssl_available_certificate_files
      self.ssl_available_files.first
    end

    #
    # This returns an array of files for the domain that contain valid keys.
    #
    def ssl_available_key_files
      self.ssl_available_files.last
    end

    #
    # Tests each of the available key and certificate files, until a matching
    # pair is found.  Returns an array of [certificate filename, key_filename],
    # or nil if no match is found.
    #
    # The order in which keys and certficates are matched is determined by
    # ssl_available_files.
    #
    def ssl_find_matching_certificate_and_key(dir = self.config_dir)
      #
      # Find the certificates and keys
      #
      certificate_files, key_files = self.ssl_available_files(dir)

      return nil if certificate_files.empty? or key_files.empty?

      #
      # Test each certificate...
      certificate_files.each do |cert_fn|
        cert = OpenSSL::X509::Certificate.new(File.read(cert_fn))
        #
        # ...with each key
        key_files.each do |key_fn|
          key = OpenSSL::PKey::RSA.new(File.read(key_fn))
          #
          # This tests the private key, and returns the current certificate and
          # key if they verify.
          return [cert_fn, key_fn] if cert.check_private_key(key)
        end
      end

      #
      # Return nil if no matching keys and certs are found
      return nil
    end

    #
    # This method performs a variety of checks on an SSL certificate and key:
    #
    # * Is the certificate valid for this domain name or any of its aliases
    # * Has the certificate started yet?
    # * Has the certificate expired?
    #
    # If any of these checks fail, a warning is raised.
    #
    # * Does the key match the certificate?
    # * If the certificate is not self-signed, does it need a bundle?
    #
    # If either of these last two checks fail, a
    # OpenSSL::X509::CertificateError is raised.
    #
    def ssl_verify(certificate = self.ssl_certificate, key = self.ssl_key, store = self.ssl_certificate_store, strict_checking=false)
      #
      # Firstly check that the certificate is valid for the domain or one of its aliases.
      #
      unless ([self.name] + self.aliases).any? { |domain_alias| OpenSSL::SSL.verify_certificate_identity(certificate, domain_alias) }
        msg = "The certificate subject is not valid for this domain #{self.name}."
        if strict_checking
          raise OpenSSL::X509::CertificateError, msg
        else
          warn "\t#{msg}" if $VERBOSE
        end
      end

      # Check that the certificate is current
      #
      #
      if certificate.not_before > Time.now
        msg = "The certificate for #{self.name} is not valid yet."
        if strict_checking
          raise OpenSSL::X509::CertificateError, msg
        else
          warn "\t#{msg}" if $VERBOSE
        end
      end

      if certificate.not_after < Time.now
        msg = "The certificate for #{self.name} has expired."
        if strict_checking
          raise OpenSSL::X509::CertificateError, msg
        else
          warn "\t#{msg}" if $VERBOSE
        end
      end

      # Next check that the key matches the certificate.
      #
      #
      unless certificate.check_private_key(key)
        raise OpenSSL::X509::CertificateError, "The certificate's public key does not match the supplied private key for #{self.name}."
      end

      #
      # Now check the signature.
      #
      # First see if we can verify it using our own private key, i.e. the
      # certificate is self-signed.
      #
      if certificate.verify(key)
        puts "\tUsing a self-signed certificate for #{self.name}." if $VERBOSE

      #
      # Otherwise see if we can verify it using the certificate store,
      # including any bundle that has been uploaded.
      #
      elsif store.is_a?(OpenSSL::X509::Store) and store.verify(certificate)
        puts "\tUsing certificate signed by #{certificate.issuer.to_s} for #{self.name}" if $VERBOSE

      #
      # If we can't verify -- raise an error if strict_checking is enabled
      #
      else
        msg =  "Certificate signature does not verify for #{self.name} -- maybe a bundle is missing?"
        if strict_checking
          raise OpenSSL::X509::CertificateError, msg
        else
          warn "\t#{msg}" if $VERBOSE
        end
      end

      true
    end

    #
    # Returns the SSL provider name.  If the `ssl-provider` is unset, the first
    # available provider is chosen.  If the name is set to `false` then false
    # is returned.  If no provider could be found, false is returned.  If the
    # provider name is "bad", false is returned.
    #
    def ssl_provider
      provider = get_param("ssl-provider", self.config_dir)

      return false if false == provider

      if provider.nil?
        if Symbiosis::SSL::PROVIDERS.first.to_s =~ /.*::([^:]+)$/
          provider = $1.downcase
        end
      end

      return false unless provider.is_a?(String)

      unless provider =~ /^[a-z0-9_]+$/
        warn "\tBad ssl-provider for #{self.name}" if $VERBOSE
        return false
      end

      provider.chomp
    end

    #
    # Returns the SSL provider class, or nil if `ssl-provider` is explicitly
    # set to "false" for this domain.  If `ssl-provider` class is unset, the
    # first available provider is used.  The `ssl-provider` doesn't map to a
    # class name, then nil is returned.
    #
    def ssl_provider_class
      provider_name = self.ssl_provider

      return nil if false == provider_name

      if provider_name.is_a?(String)
        provider = Symbiosis::SSL::PROVIDERS.find{|k| k.to_s =~ /::#{provider_name}$/i}
      else
        provider = Symbiosis::SSL::PROVIDERS.first
      end

      provider
    end

    #
    # This fetches the certificate from using ssl_provider_class.  If
    # ssl_provider_class does not return a suitable Class, nil is returned.
    #
    # Returns an hash of
    #
    #  { :key, :certificate, :request, :bundle}
    #
    def ssl_fetch_certificate
      ssl_provider_class = self.ssl_provider_class

      unless ssl_provider_class.is_a?(Class) and
        ssl_provider_class.instance_methods.include?(:verify_and_request_certificate!)
        return nil
      end

      ssl_provider = ssl_provider_class.new(self)
      ssl_provider.register unless ssl_provider.registered?
      ssl_provider.verify_and_request_certificate!


      return { :key         => ssl_provider.key,
        :request     => ssl_provider.request,
        :bundle      => ssl_provider.bundle,
        :certificate => ssl_provider.certificate }
    end

    #
    # We expect the certificate, key, and bundle in a pattern like
    # /srv/example.com/config/ssl/set/.
    #
    def ssl_current_set
      current_dir = File.join(self.config_dir, "ssl", "current")
      stat = nil

      begin
        stat = File.lstat(current_dir)
      rescue Errno::ENOENT
        warn "\t#{current_dir} not found" if $VERBOSE
        return nil
      end

      while stat.symlink? do
        parent_dir  = File.dirname(current_dir)
        current_dir = File.expand_path(File.readlink(current_dir), parent_dir)
        begin
          stat = File.lstat(current_dir)
        rescue Errno::ENOENT
          break
        end
      end

      unless stat.directory?
        warn "\tUnable to determine current SSL set -- #{current_dir} isn't a directory." if $VERBOSE
        return nil
      end

      parent_dir, set = File.split(current_dir)
      unless parent_dir == File.join(self.config_dir, "ssl")
        warn "\tTHe current set of certificates (#{current_dir}) are outside the domain's ssl directory. Ignoring." if $VERBOSE
        return nil
      end

      set
    end

    #
    # Returns the directory
    #
    def ssl_available_sets
      sets = []

      Dir.glob(File.join(self.config_dir, 'ssl' ,'*')).each do |cert_dir|

        #
        # Not interested in files etc.
        #
        next unless File.directory?(cert_dir)


        this_set = File.basename(cert_dir)

        #
        # Always miss out the "current" set
        #
        next if this_set == "current"

        #
        # If a matching key/cert pair cannot be found, move on.
        #
        next if (this_cert, this_key = ssl_find_matching_certificate_and_key(cert_dir)).nil?

        begin
          this_cert  = OpenSSL::X509::Certificate.new(get_param(File.basename(this_cert), cert_dir))
          this_key   = OpenSSL::PKey::RSA.new(get_param(File.basename(this_key), cert_dir))
          this_store = self.ssl_certificate_store(cert_dir)
        rescue OpenSSL::OpenSSLError => err
          warn "\t#{err.to_s}" if $VERBOSE
          next
        end

        #
        # If this certificate verifies, add it to our list
        #
        begin
          self.ssl_verify(this_cert, this_key, this_store, true)
        rescue OpenSSL::OpenSSLError => err
          warn "\t#{err.to_s}" if $VERBOSE
          next
        end

        sets << this_set
      end

      return sets.sort
    end

    #
    # This method symlinks /srv/example.com/config/ssl/current to the latest
    # set of certificates discovered by #ssl_available_sets. This returns true
    # if a rollover was performed, or false otherwise.
    #
    def ssl_rollover
      current = self.ssl_current_set
      latest  = self.ssl_available_sets.last

      if latest.nil?
        warn "\tNo valid sets of certificates found." if $VERBOSE
        return false
      end

      #
      # If the current certificate is current, do nothing.
      #
      return false if current == latest

      current_dir = File.join(self.config_dir, "ssl", "current")

      begin
        stat = File.lstat(current_dir)
      rescue Errno::ENOENT
        stat = nil
      end

      unless stat.nil? or stat.symlink?
        warn "\t#{current_dir} is not a symlink.  Unwilling to roll over." if $VERBOSE
        return false
      end

      #
      # To create a symlink with the correct uid/gid when running as root, we
      # need to set our effective UID/GID.
      #
      Process.egid = self.gid if Process.gid == 0
      Process.euid = self.uid if Process.uid == 0

      File.unlink(current_dir) unless stat.nil?
      File.symlink(latest, current_dir)

      Process.euid = 0 if Process.uid == 0
      Process.egid = 0 if Process.gid == 0

      return true
    end

  end

end
