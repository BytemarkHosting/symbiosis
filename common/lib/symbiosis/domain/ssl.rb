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
    # Add a path with extra SSL certs for testing
    #
    def ssl_add_ca_path(path)
      @ssl_ca_paths = [] unless defined? @ssl_ca_paths

      @ssl_ca_paths << path if File.directory?(path)
    end

    #
    # Is SSL enabled for the domain?
    #
    # SSL is enabled if an IP has been set, as well as matching key and certificate.
    #
    def ssl_enabled?
      self.ip and not self.ssl_find_matching_certificate_and_key.nil? 
    end

    #
    # Do we redirect to the SSL only version of this site?
    #
    def ssl_mandatory?
      get_param("ssl-only", config_dir)
    end

    #
    # Returns the X509 certificate object
    #
    def ssl_x509_certificate
      if self.ssl_certificate_file.nil?
        nil
      else
        OpenSSL::X509::Certificate.new(File.read(self.ssl_certificate_file))
      end
    end

    #
    # Returns the RSA key object
    #
    def ssl_key
      if self.ssl_key_file.nil?
        nil
      else
        OpenSSL::PKey::RSA.new(File.read(self.ssl_key_file))
      end
    end

    #
    # Returns the certificate chain file, if one exists, or one has been set.
    #
    def ssl_certificate_chain_file
      @ssl_certificate_chain_file = nil unless defined? @ssl_certificate_chain_file

      if @ssl_certificate_chain_file.nil? and File.exists?( File.join( self.config_dir,"ssl.bundle" ) )
        @ssl_certificate_chain_file = File.join( self.config_dir,"ssl.bundle" )
      end

      if @ssl_certificate_chain_file and File.exists?(@ssl_certificate_chain_file)
        @ssl_certificate_chain_file 
      else
        nil
      end
    end

    alias ssl_bundle_file ssl_certificate_chain_file

    #
    # Returns the X509 certificate store, including any specified chain file
    #
    def ssl_certificate_store
      certificate_store = OpenSSL::X509::Store.new
      certificate_store.set_default_paths
      @ssl_ca_paths.each{|path| certificate_store.add_path(path)}
      certificate_store.add_file(self.ssl_certificate_chain_file) unless self.ssl_certificate_chain_file.nil?
      certificate_store
    end
                
    #
    # Return the available certificate files
    #
    def ssl_available_certificate_files
      # Try a number of permutations
      %w(combined key crt cert pem).collect do |ext|
        #
        #
        if get_param("ssl.#{ext}", self.config_dir)
          "ssl.#{ext}"
        else
          nil
        end

      end.reject do |fn|
        begin
          raise Errno::ENOENT if fn.nil?
          #
          # See if there is a key in the same file
          #
          this_key  = OpenSSL::PKey::RSA.new(File.read(fn))
          this_cert = OpenSSL::X509::Certificate.new(File.read(fn))

          # 
          # If the cert can't validate the private key, reject!
          #
          true unless this_cert.check_private_key(this_key)
        rescue OpenSSL::OpenSSLError
          #
          # Keep if there is no key in this file
          #
          false
        rescue Errno::ENOENT
          # 
          # Reject if the file can't be found
          #
          true
        end  
      end
    end

    #
    # Return the available key files
    #
    def ssl_available_key_files
      # Try a number of permutations
      %w(combined key cert crt pem).collect do |ext|

        fn = File.join(self.config_dir, "ssl.#{ext}")

        #
        # Try to open and read the key
        #
        begin
          OpenSSL::PKey::RSA.new(File.read(fn))
          fn
        rescue Errno::ENOENT, Errno::EPERM
          # Skip if the file doesn't exist
          nil
        rescue OpenSSL::OpenSSLError
          # Skip if we can't read the cert
          nil
        end
      end.reject do |fn|
        begin
          raise Errno::ENOENT if fn.nil?
          #
          # See if there is a key in the same file
          #
          this_cert = OpenSSL::X509::Certificate.new(File.read(fn))
          this_key  = OpenSSL::PKey::RSA.new(File.read(fn))

          # 
          # If the cert can't validate the private key, reject!
          #
          true unless this_cert.check_private_key(this_key)
        rescue OpenSSL::OpenSSLError

          #
          # Keep if there is no certificate in this file
          #
          false
        rescue Errno::ENOENT

          # 
          # Reject if the file can't be found
          #
          true
        end  
      end
    end

    #
    # Tests each of the available key and certificate files, until a matching
    # pair is found.  Returns an array of [certificate filename, key_filename],
    # or nil if no match is found.
    #
    def ssl_find_matching_certificate_and_key
      #
      # Test each certificate...
      self.ssl_available_certificate_files.each do |cert_fn|
        cert = OpenSSL::X509::Certificate.new(File.read(cert_fn))
        #
        # ...with each key
        self.ssl_available_key_files.each do |key_fn|
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
      # Firstly check that the certificate is valid for the domain.
      #
      #
      unless OpenSSL::SSL.verify_certificate_identity(self.ssl_x509_certificate, @domain) or OpenSSL::SSL.verify_certificate_identity(self.ssl_x509_certificate, "www.#{@domain}")
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
