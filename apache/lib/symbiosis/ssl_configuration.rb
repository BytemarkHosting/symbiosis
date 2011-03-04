require 'openssl'

#
# A helper class which copes with SSL-domains.
#
#
module Symbiosis
  class SSLConfiguration

    #
    # The domain this object is working with.
    #
    attr_reader   :domain
    attr_accessor :root_path, :certificate_file, :key_file
    attr_writer   :certificate_chain_file

    #
    # Constructor.
    #
    def initialize( domain )
      @domain = domain
      @certificate = nil
      @key = nil
      @bundle = nil
      @root_path = "/"
      @ca_paths = []
    end

    #
    # Returns the apache2 configuration directory
    #
    def apache_dir
      File.join(@root_path, "etc", "apache2")
    end

    #
    # Returns the configuration directory for this domain
    #
    def config_dir
      File.join(@root_path, "srv", @domain, "config")
    end

    #
    # Add a path with extra SSL certs for testing
    #
    def add_ca_path(path)
      @ca_paths << path if File.directory?(path)
    end

    #
    # Is SSL enabled for the domain?
    #
    # SSL is enabled if an IP has been set, as well as matching key and certificate.
    #
    def ssl_enabled?
      self.ip and not self.find_matching_certificate_and_key.nil? 
    end

    #
    # Is there an Apache site enabled for this domain?
    #
    def site_enabled?
      File.exists?( File.join( self.apache_dir, "sites-enabled", "#{@domain}.ssl" )  )
    end

    #
    # Do we redirect to the SSL only version of this site?
    #
    def mandatory_ssl?
      File.exists?( File.join( config_dir , "ssl-only" ) ) 
    end

    #
    # Remove the apache file.
    #
    def remove_site

      if ( File.exists?( "#{self.apache_dir}/sites-enabled/#{@domain}.ssl" ) )
        File.unlink( "#{self.apache_dir}/sites-enabled/#{@domain}.ssl" )
      end

      if ( File.exists?( "#{self.apache_dir}/sites-available/#{@domain}.ssl" ) )
        File.unlink( "#{self.apache_dir}/sites-available/#{@domain}.ssl" )
      end
    end

    #
    # Return the IP for this domain, or nil if no IP has been set.
    #
    def ip
      if File.exists?( File.join( self.config_dir, "ip" ) )
        File.open( File.join( self.config_dir, "ip" ) ){|fh| fh.readlines}.first.chomp
      else
        nil
      end
    end

    #
    # Returns the X509 certificate object
    #
    def certificate
      if self.certificate_file.nil?
        nil
      else
        OpenSSL::X509::Certificate.new(File.read(self.certificate_file))
      end
    end

    #
    # Returns the RSA key object
    #
    def key
      if self.key_file.nil?
        nil
      else
        OpenSSL::PKey::RSA.new(File.read(self.key_file))
      end
    end

    #
    # Returns the certificate chain file, if one exists, or one has been set.
    #
    def certificate_chain_file
      if @certificate_chain_file.nil? and File.exists?( File.join( self.config_dir,"ssl.bundle" ) )
        @certificate_chain_file = File.join( self.config_dir,"ssl.bundle" )
      end
      @certificate_chain_file
    end

    alias bundle_file certificate_chain_file

    #
    # Returns the X509 certificate store, including any specified chain file
    #
    def certificate_chain
      certificate_chain = OpenSSL::X509::Store.new
      certificate_chain.set_default_paths
      @ca_paths.each{|path| certificate_chain.add_path(path)}
      certificate_chain.add_file(self.certificate_chain_file) unless self.certificate_chain_file.nil?
      certificate_chain
    end
                
    #
    # Return the available certificate files
    #
    def available_certificate_files
      # Try a number of permutations
      %w(combined key crt cert pem).collect do |ext|

        fn = File.join(self.config_dir, "ssl.#{ext}")

        #
        # Try and open the certificate
        #
        begin
          OpenSSL::X509::Certificate.new(File.read(fn))
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
    def available_key_files
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
    def find_matching_certificate_and_key
      #
      # Test each certificate...
      self.available_certificate_files.each do |cert_fn|
        cert = OpenSSL::X509::Certificate.new(File.read(cert_fn))
        #
        # ...with each key
        self.available_key_files.each do |key_fn|
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

    def verify
    # Firstly check that the certificate is valid for the domain.
    #
    #
    unless OpenSSL::SSL.verify_certificate_identity(self.certificate, @domain) or OpenSSL::SSL.verify_certificate_identity(self.certificate, "www.#{@domain}")
      raise OpenSSL::X509::CertificateError, "Certificate subject is not valid for this domain."
    end

    # Check that the certificate is current
    # 
    #
    if self.certificate.not_before > Time.now 
      raise OpenSSL::X509::CertificateError, "Certificate is not valid yet."
    end

    if self.certificate.not_after < Time.now 
      raise OpenSSL::X509::CertificateError, "Certificate has expired."
    end

    # Next check that the key matches the certificate.
    #
    #
    unless self.certificate.check_private_key(self.key)
      raise OpenSSL::X509::CertificateError, "Private key does not match certificate."
    end
   
    # 
    # Now check the signature
    #
    if self.certificate.issuer.to_s == self.certificate.subject.to_s
      #
      # Firstly for a self-signed certificate check the signature on the
      # certificate was made by our key.
      #
      # This should never fail!
      unless self.certificate.verify(self.key)
        raise OpenSSL::X509::CertificateError, "Private key does not match that on the certificate's signature."
      end
    else
      # 
      # Otherwise for a CA-signed certificate, make sure the signature can be
      # verified using the usual store of certificates on the machine,
      # including any bundle that has been left lying around.
      #
      unless self.certificate_chain.verify(self.certificate)
        raise OpenSSL::X509::CertificateError, "Certificate does not verify -- maybe a bundle is missing?" 
      end
    end

    true
  end

  #
  # Update Apache to create a site for this domain.
  #
  def create_ssl_site( tf = File.join(self.root_path, "etc/symbiosis/apache.d/ssl.template.erb") )

    #
    #  Read the template file.
    #
    content = File.open( tf, "r" ).read()

    #
    #  Create a template object.
    #
    template = ERB.new( content )

    #
    # Write out to sites-enabled
    #
    File.open( File.join( self.apache_dir, "sites-available/#{@domain}.ssl", "w" ) ) do |file|
      file.write template.result(binding)
    end

    #
    #  Now link in the file
    #
    File.symlink( File.join( self.apache_dir, "sites-available/#{@domain}.ssl" ),
                  File.join( self.apache_dir, "sites-enabled/#{@domain}.ssl"   ) )

  end

  #
  # Does the SSL site need updating because a file is more
  # recent than the generated Apache site?
  #
  def outdated?

    #
    # creation time of the (previously generated) SSL-site.
    #
    site = File.mtime( "#{self.apache_dir}/sites-available/#{@domain}.ssl" )


    #
    #  For each configuration file see if it is more recent
    #
    files = %w( ssl.combined ssl.key ssl.bundle ip )

    files.each do |file|
      if ( File.exists?( File.join( self.config_dir, file ) ) )
        mtime = File.mtime(  File.join( self.config_dir, file ) )
        if ( mtime > site )
          return true
        end
      end
    end

    false
  end

end
end
