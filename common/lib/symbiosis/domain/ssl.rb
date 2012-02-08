require 'symbiosis/domain'
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
    def ssl_certificate_chain_file
      if get_param("ssl.bundle", self.config_dir)
        File.join( self.config_dir,"ssl.bundle" )
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
    def ssl_certificate_store
      @ssl_ca_paths ||= []

      certificate_store = OpenSSL::X509::Store.new
      certificate_store.set_default_paths

      @ssl_ca_paths.each{|path| certificate_store.add_path(path)}
      certificate_store.add_file(self.ssl_certificate_chain_file) unless self.ssl_certificate_chain_file.nil?
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
    def ssl_available_files
      certificate_files = []
      key_files = []

      # 
      # Try a number of permutations
      #
      %w(combined key crt cert pem).each do |ext|
        #
        # See if the file exists.
        #
        contents = get_param("ssl.#{ext}", self.config_dir)

        #
        # If it doesn't exist/is unreadble, return nil.
        #
        next if false == contents
 
        this_fn = File.join(self.config_dir, "ssl.#{ext}")

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
          certificate_files << this_fn
          key_files         << this_fn
        elsif this_key and !this_cert
          key_files << this_fn
        elsif this_cert and !this_key
          certificate_files << this_fn
        end
      end

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
    def ssl_find_matching_certificate_and_key
      #
      # Find the certificates and keys
      #
      certificate_files, key_files = self.ssl_available_files

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
    def ssl_verify(certificate = self.ssl_x509_certificate, key = self.ssl_key, store = self.ssl_certificate_store)

      #
      # Firstly check that the certificate is valid for the domain or one of its aliases.
      #
      unless self.aliases.any? { |domain_alias| OpenSSL::SSL.verify_certificate_identity(certificate, domain_alias) }
        warn "\tThe certificate subject is not valid for this domain." if $VERBOSE
      end

      # Check that the certificate is current
      # 
      #
      if certificate.not_before > Time.now 
        warn "\tThe certificate is not valid yet." if $VERBOSE
      end

      if certificate.not_after < Time.now 
        warn "\tThe certificate has expired." if $VERBOSE
      end

      # Next check that the key matches the certificate.
      #
      #
      unless certificate.check_private_key(key)
        raise OpenSSL::X509::CertificateError, "The certificate's public key does not match the supplied private key."
      end
     
      # 
      # Now check the signature.
      #
      # First see if we can verify it using our own private key, i.e. the
      # certificate is self-signed.
      #
      if certificate.verify(key)
        puts "\tUsing a self-signed certificate." if $VERBOSE

      #
      # Otherwise see if we can verify it using the certificate store,
      # including any bundle that has been uploaded.
      #
      elsif store.verify(certificate)
        puts "\tUsing certificate signed by #{certificate.issuer.to_s}" if $VERBOSE

      #
      # If we can't verify -- raise an error.
      #
      else
        raise OpenSSL::X509::CertificateError, "Certificate signature does not verify -- maybe a bundle is missing?" 
      end

      true
    end

  end

end
