require 'symbiosis/domain'
require 'openssl'
require 'erb'

#
# A helper class which copes with SSL-domains.
#
#
module Symbiosis

  class Domain

    #
    # Is SSL enabled for the domain?
    #
    # SSL is enabled if there is a matching key and certificate.
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

    def ssl_x509_certificate_file
      @ssl_x509_certificate_file ||= nil
      
      if @ssl_x509_certificate_file.nil?
        @ssl_x509_certificate_file, @ssl_key_file = self.ssl_find_matching_certificate_and_key
      end

      @ssl_x509_certificate_file
    end

    alias ssl_certificate_file ssl_x509_certificate_file

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

    def ssl_key_file
      @ssl_key_file ||= nil

      if @ssl_key_file.nil?
        @ssl_x509_certificate_file, @ssl_key_file = self.ssl_find_matching_certificate_and_key
      end

      @ssl_key_file
    end

    def ssl_key_file=(f)
      @ssl_key_file = f
    end


    #
    # Returns the RSA key object
    #
    def ssl_key
      unless self.ssl_key_file.nil?
        OpenSSL::PKey::RSA.new(File.read(self.ssl_key_file))
      else
        nil
      end
    end

    #
    # Returns the certificate chain file, if one exists, or one has been set.
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
    # Add a path with extra SSL certs for testing
    #
    def ssl_add_ca_path(path)
      @ssl_ca_paths ||= [] 

      @ssl_ca_paths << path if File.directory?(path)
    end

    #
    # Returns the X509 certificate store, including any specified chain file.
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
    # Return the available certificate/key files
    #
    # It will return an array [[certificate_files] , [key_files]]
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
    
    def ssl_available_certificate_files
      self.ssl_available_files.first
    end

    def ssl_available_key_files
      self.ssl_available_files.last
    end

    #
    # Tests each of the available key and certificate files, until a matching
    # pair is found.  Returns an array of [certificate filename, key_filename],
    # or nil if no match is found.
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

    def ssl_verify
      #
      # Firstly check that the certificate is valid for the domain.
      #
      unless OpenSSL::SSL.verify_certificate_identity(self.ssl_x509_certificate, self.name) or
             OpenSSL::SSL.verify_certificate_identity(self.ssl_x509_certificate, "www.#{self.name}")

        raise OpenSSL::X509::CertificateError, "The certificate subject is not valid for this domain."
      end

      # Check that the certificate is current
      # 
      #
      if self.ssl_x509_certificate.not_before > Time.now 
        raise OpenSSL::X509::CertificateError, "The certificate is not valid yet."
      end

      if self.ssl_x509_certificate.not_after < Time.now 
        raise OpenSSL::X509::CertificateError, "The certificate has expired."
      end

      # Next check that the key matches the certificate.
      #
      #
      unless self.ssl_x509_certificate.check_private_key(self.ssl_key)
        raise OpenSSL::X509::CertificateError, "The certificate's public key does not match the supplied private key."
      end
     
      # 
      # Now check the signature.
      #
      # First see if we can verify it using our own private key, i.e. the
      # certificate is self-signed.
      #
      if self.ssl_x509_certificate.verify(self.ssl_key)
        puts "\tUsing a self-signed certificate." if $VERBOSE

      #
      # Otherwise see if we can verify it using the certificate store,
      # including any bundle that has been uploaded.
      #
      elsif self.ssl_certificate_store.verify(self.ssl_x509_certificate)
        puts "\tUsing certificate signed by #{self.ssl_x509_certificate.issuer.to_s}" if $VERBOSE

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
