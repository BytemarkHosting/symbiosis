require 'openssl'
require 'erb'

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
      @certificate_chain_file = nil
    end

    #
    # Returns the apache2 configuration directory
    #
    def apache_dir
      File.join(@root_path, "etc", "apache2")
    end

    #
    # Returns the site-enabled filename
    #
    def sites_enabled_file
      File.join(self.apache_dir,"sites-enabled","#{@domain}.conf")
    end

    def sites_available_file
      File.join(self.apache_dir,"sites-available","#{@domain}.conf")
    end

    #
    # Returns the DocumentRoot for the domain.
    #
    def domain_directory
      File.join(@root_path, "srv", @domain)
    end

    #
    # Returns the configuration directory for this domain
    #
    def config_dir
      File.join(self.domain_directory, "config")
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
      File.exists?( self.sites_enabled_file )
    end

    #
    # Do we redirect to the SSL only version of this site?
    #
    def mandatory_ssl?
      File.exists?( File.join( config_dir , "ssl-only" ) ) 
    end

    #
    # Returns the bundle filename + the apache directive
    #
    def bundle
      return "" unless bundle_file
      
      "SSLCertificateChainFile #{config_dir}/ssl.bundle"
    end

    #
    # Returns the certificate (+key) snippet 
    #
    def certificate
      return nil unless certificate_file and key_file

      if certificate_file == key_file
        "SSLCertificateFile #{certificate_file}"
      else
        "SSLCertificateFile #{certificate_file}\nSSLCertificateKeyFile #{key_file}"
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
    def x509_certificate
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

      if @certificate_chain_file and File.exists?(@certificate_chain_file)
        @certificate_chain_file 
      else
        nil
      end
    end

    alias bundle_file certificate_chain_file

    #
    # Returns the X509 certificate store, including any specified chain file
    #
    def certificate_store
      certificate_store = OpenSSL::X509::Store.new
      certificate_store.set_default_paths
      @ca_paths.each{|path| certificate_store.add_path(path)}
      certificate_store.add_file(self.certificate_chain_file) unless self.certificate_chain_file.nil?
      certificate_store
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
      unless OpenSSL::SSL.verify_certificate_identity(self.x509_certificate, @domain) or OpenSSL::SSL.verify_certificate_identity(self.x509_certificate, "www.#{@domain}")
        raise OpenSSL::X509::CertificateError, "The certificate subject is not valid for this domain."
      end

      # Check that the certificate is current
      # 
      #
      if self.x509_certificate.not_before > Time.now 
        raise OpenSSL::X509::CertificateError, "The certificate is not valid yet."
      end

      if self.x509_certificate.not_after < Time.now 
        raise OpenSSL::X509::CertificateError, "The certificate has expired."
      end

      # Next check that the key matches the certificate.
      #
      #
      unless self.x509_certificate.check_private_key(self.key)
        raise OpenSSL::X509::CertificateError, "The certificate's public key does not match the supplied private key."
      end
     
      # 
      # Now check the signature.
      #
      # First see if we can verify it using our own private key, i.e. the
      # certificate is self-signed.
      #
      if self.x509_certificate.verify(self.key)
        puts "\tUsing a self-signed certificate." if $VERBOSE

      #
      # Otherwise see if we can verify it using the certificate store,
      # including any bundle that has been uploaded.
      #
      elsif self.certificate_store.verify(self.x509_certificate)
        puts "\tUsing certificate signed by #{self.x509_certificate.issuer.to_s}" if $VERBOSE

      #
      # If we can't verify -- raise an error.
      #
      else
        raise OpenSSL::X509::CertificateError, "Certificate signature does not verify -- maybe a bundle is missing?" 
      end

      true
    end

    #
    # Update Apache to create a site for this domain.
    #
    def config_snippet( tf = File.join(self.root_path, "etc/symbiosis/apache.d/ssl.template.erb") )

      #
      #  Read the template file.
      #
      content = File.open( tf, "r" ).read()

      #
      #  Create a template object.
      #
      ERB.new( content ).result( binding )
    end

    def write_configuration(config = self.config_snippet)
      #
      # Write out to sites-enabled
      #
      File.open( self.sites_available_file, "w+" ) do |file|
        file.write config
        file.puts "# Checksum MD5 "+OpenSSL::Digest::MD5.new(config).hexdigest
      end
    end

    def configuration_ok?
      return false unless File.executable?("/usr/sbin/apache2")

      output = []
      IO.popen( "/usr/sbin/apache2 -C 'UseCanonicalName off' -C 'Include /etc/apache2/mods-enabled/*.load' -C 'Include /etc/apache2/mods-enabled/*.conf' -f #{self.sites_available_file} -t 2>&1 ") {|io| output = io.readlines }

      warn output.collect{|o| "\t"+o}.join unless "Syntax OK" == output.last.chomp or $VERBOSE

      "Syntax OK" == output.last.chomp
    end

    def enable_site
      if configuration_ok?
        #  Now link in the file
        #
        File.symlink( self.sites_available_file, self.sites_enabled_file )
      end
    end
    
    #
    # Remove the apache file.
    #
    def disable_site
      File.unlink( self.sites_enabled_file ) if File.exists?( self.sites_enabled_file )
    end

    #
    # Does the SSL site need updating because a file is more
    # recent than the generated Apache site?
    #
    def outdated?

      #
      # creation time of the (previously generated) SSL-site.
      #
      site = File.mtime( self.sites_available_file )

      #
      #  For each configuration file see if it is more recent
      #
      %w( ssl.combined ssl.key ssl.bundle ip ).each do |file|
        file = File.join( self.config_dir, file )
        return true if File.exists?( file ) and File.mtime( file ) > site 
      end

      false
    end


    #
    # This opens the config sni
    #
    def changed?
      #
      # Read the snippet
      #
      snippet = File.readlines(self.sites_available_file)
      
      #
      # We expect the checksum to be the last line of the file
      #
      if snippet.last.chomp =~ /^# Checksum MD5 ([a-f0-9]{32,32})$/
        #
        # OK we've found the checksum
        #

        supposed_checksum = $1

        #
        # Pop off the last line, as this isn't part of the checksum
        #
        snippet.pop
        
        #
        # And compare to the calculated checksum of the rest of the snippet
        #
        return OpenSSL::Digest::MD5.new(snippet.join).hexdigest != supposed_checksum
      
      #
      # We're OK if the file has a big warning in it.
      #
      elsif snippet.any?{|l| "# DO NOT EDIT THIS FILE - CHANGES WILL BE OVERWRITTEN" == l.chomp}
        #
        # So return true
        #
        return false

      end

      #
      # Assume the file has been edited.  
      #
      puts "\tCould not find checksum or big warning." if $VERBOSE

      true
    end

  end
end
