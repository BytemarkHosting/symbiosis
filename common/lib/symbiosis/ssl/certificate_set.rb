require 'symbiosis/domain'
require 'symbiosis/ssl'
require 'symbiosis/utils'
require 'openssl'
require 'tmpdir'
require 'erb'

module Symbiosis

  class SSL

    class CertificateSet

      include Comparable
      include Symbiosis::Utils

      def initialize(domain, directory=nil)
        raise ArgumentError, "domain must be a Symbiosis::Domain" unless domain.is_a?(Symbiosis::Domain)

        @domain           = domain
        @certificate      = @key      = @bundle      = @request = nil
        @certificate_file = @key_file = @bundle_file = @request_file = nil
        @name = @directory = nil

        self.directory = directory if directory
      end

      def domain
        @domain
      end

      def name
        @name
      end

      #
      # Set the name for this set of certificates
      #
      def name=(n)
        raise ArgumentError, "Bad SSL set name #{n.inspect}" unless n.to_s =~ /^[a-z0-9_:-]+$/i
        
        @name = n
 
        if self.directory.nil?
          if "legacy" == @name
            self.directory = self.domain.config_dir
          elsif self.name.is_a?(String)
            self.directory = File.join(self.domain.config_dir, "ssl", @name)
          end
        end

        @name
      end

      def directory
        @directory
      end

      #
      # Sets the directory name.  It is expanded relative to the domain's
      # config directory.
      #
      def directory=(d)
        raise Errno::ENOTDIR.new d if File.exist?(d) and !File.directory?(d)
        
        @directory = File.expand_path(d, File.join(self.domain.config_dir, "ssl"))

        if self.name.nil?
          if self.domain.config_dir == @directory
            self.name = "legacy"
          else
            self.name = File.basename(@directory)
          end
        end

        @directory
      end

      #
      # Sort by name.
      #
      def <=>(other)
        self.name <=> other.name
      end

      #
      # Searches for a SSL certificate using find_matching_certificate_and_key,
      # and returns the certificate's filename, or nil if nothing could be
      # found.
      #
      def certificate_file
        @certificate_file ||= nil

        if @certificate_file.nil?
          @certificate_file, @key_file = self.find_matching_certificate_and_key
        end

        @certificate_file
      end

      #
      # Sets the domains SSL certificate filename.
      #
      def certificate_file=(f)
        @certificate_file = f
      end

      #
      # Returns the X509 certificate object, or nil if the certificate could
      # not be found, or its contents unparseable.
      #
      def certificate
        return nil if self.certificate_file.nil?

        data = get_param(*(File.split(self.certificate_file).reverse))

        return @certificate = OpenSSL::X509::Certificate.new(data)

      rescue OpenSSL::OpenSSLError => err
        warn "\tSSL set #{name}: Could not parse data in #{self.certificate_file}: #{err}"
        return nil
      end

      def certificate=(c)
        @certificate = c
      end

      #
      # Searches for the domain's SSL key using
      # find_matching_certificate_and_key, and returns the key's filename, or
      # nil if nothing could be found.
      #
      def key_file
        @key_file ||= nil

        if @key_file.nil?
          @certificate_file, @key_file = self.find_matching_certificate_and_key
        end

        @key_file
      end

      #
      # Sets the domains's SSL key filename.
      #
      def key_file=(f)
        @key_file = f
      end

      #
      # Returns the directory's SSL key as an OpenSSL::PKey::RSA object, or nil
      # if no key file could be found, or could not be read.
      #
      def key
        return nil if self.key_file.nil?

        data = get_param(*(File.split(self.key_file).reverse))

        return @key = OpenSSL::PKey::RSA.new(data)

      rescue OpenSSL::OpenSSLError => err
        warn "\tSSL set #{name}: Could not parse data in #{self.key_file}: #{err}"
        return nil
      end

      def request_file
        return @request_file unless @request_file.nil?
        
        fn = File.join(self.directory, "ssl.csr")

        @request_file = fn if File.exist?(fn)
        
        @request_file
      end

      def request_file=(r)
        @request_file = r
      end

      def request
        return nil if self.request_file.nil?

        @request = get_param(*(File.split(self.request_file).reverse))
      end

      #
      # 
      #
      def certificate_chain_file=(f)
        @certificate_chain_file = f
      end

      #
      # Returns the certificate chain filename, if one exists, or one has been
      # set, or nil if nothing could be found.
      #
      def certificate_chain_file
        return @certificate_chain_file unless @certificate_chain_file.nil?

        fn = File.join(self.directory, "ssl.bundle")

        @certificate_chain_file = fn if File.exist?(fn)

        @certificate_chain_file
      end

      alias bundle_file certificate_chain_file

      def certificate_chain
        return nil if self.request_file.nil?

        @request = get_param(*(File.split(self.certificate_chain_file).reverse))
      end

      #
      # Add a path with extra SSL certs (for testing).
      #
      def add_ca_path(path)
        @ca_paths ||= []

        @ca_paths << path if File.directory?(path)
      end

      #
      # Sets up and returns a new OpenSSL::X509::Store.
      #
      # If any CA paths have been set using add_ca_path, then these are added to the store.
      #
      # If certificate_chain_file has been set, then this is added to the store.
      #
      # This is regenerated on every call.
      #
      def certificate_store
        @ca_paths ||= []

        certificate_store = OpenSSL::X509::Store.new
        certificate_store.set_default_paths

        @ca_paths.each{|path| certificate_store.add_path(path)}
        chain_file = self.certificate_chain_file
        begin
          certificate_store.add_file(chain_file) unless chain_file.nil?
        rescue OpenSSL::X509::StoreError
           warn "\tSSL set #{name}: Unable to add chain file to the store."
        end
        certificate_store
      end

      #
      # Return the available certificate/key files for a domain.  It will check
      # files with the following extensions for both keys and certificates.
      #  * key
      #  * crt
      #  * combined
      #  * pem
      #
      # It will return an array of certificate and key filenames that could be
      # read and parsed successfully by OpenSSL.  The array has to sub-arrays,
      # the first being certificate filenames, the second key filenames, i.e.
      # <code>[[certificates] , [keys]]</code>.  If a file contains both a
      # certificate and key, it will appear in both arrays.
      #
      def available_files
        certificates = []
        key_files = []

        #
        # Try a number of permutations
        #
        %w(combined key crt cert pem).each do |ext|
          #
          # See if the file exists.
          #
          contents = get_param("ssl.#{ext}", self.directory)

          #
          # If it doesn't exist/is unreadble, return nil.
          #
          next unless contents.is_a?(String)

          this_fn = File.join(self.directory, "ssl.#{ext}")

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
      def available_certificate_files
        self.available_files.first
      end

      #
      # This returns an array of files for the domain that contain valid keys.
      #
      def available_key_files
        self.available_files.last
      end

      #
      # Tests each of the available key and certificate files, until a matching
      # pair is found.  Returns an array of [certificate filename, key_filename],
      # or nil if no match is found.
      #
      # The order in which keys and certficates are matched is determined by
      # available_files.
      #
      def find_matching_certificate_and_key
        #
        # Find the certificates and keys
        #
        certificate_files, key_files = self.available_files

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
      def verify(certificate = self.certificate, key = self.key, store = self.certificate_store, strict_checking=false)

        unless certificate.is_a?(OpenSSL::X509::Certificate) and key.is_a?(OpenSSL::PKey::PKey)
          return false
        end

        #
        # Firstly check that the certificate is valid for the domain or one of its aliases.
        #
        unless ([@domain.name] + @domain.aliases).any? { |domain_alias| OpenSSL::SSL.verify_certificate_identity(certificate, domain_alias) }
          msg = "The certificate subject is not valid for this domain #{@domain.name}."
          if strict_checking
            raise OpenSSL::X509::CertificateError, msg
          else
            warn "\tSSL set #{name}: #{msg}" if $VERBOSE
          end
        end

        # Next check that the key matches the certificate.
        #
        #
        unless certificate.check_private_key(key)
          raise OpenSSL::X509::CertificateError, "The certificate's public key does not match the supplied private key for #{@domain.name}."
        end

        #
        # We always need a store
        #
        store = OpenSSL::X509::Store.new unless store.is_a?(OpenSSL::X509::Store)

        #
        # See if we can verify it using the certificate store,
        # including any bundle that has been uploaded.
        #
        if store.verify(certificate)
          puts "\tSSL set #{name}: certificate signed by \"#{certificate.issuer.to_s}\" for #{@domain.name}" if $VERBOSE

        elsif store.error == 18
          unless certificate.verify(key)
            raise OpenSSL::X509::CertificateError, "\tSSL set #{name}: Certificate is self signed, but the signature doesn't validate."
          end
          puts "\tSSL set #{name}: self-signed certificate for #{@domain.name}." if $VERBOSE
        else
          msg =  "Certificate is not valid for #{@domain.name} -- "
          case store.error
            when 2, 20
              msg += "the intermediate bundle is missing"
            else
              msg += store.error_string
          end

          #
          # The numeric errors are detailed in /usr/include/openssl/x509_vfy.h
          #
          msg += " (#{store.error})"

          #
          # If we can't verify -- raise an error if strict_checking is enabled
          #
          if strict_checking
            raise OpenSSL::X509::CertificateError, msg
          else
            warn "\tSSL set #{name}: #{msg}" if $VERBOSE
          end
        end

        store.error
      end


      def write
        raise ArgumentError, "The directory for this SSL certificate set has been given" if self.directory.nil?

        raise Errno::EEXIST.new self.directory if File.exists?(self.directory)
        mkdir_p(File.dirname(self.directory))

        tmpdir = Dir.mktmpdir(self.name+"-ssl-")

        combined = [:certificate, :bundle, :key].map{|k| self.__send__(k) }.flatten.compact

        set_param("ssl.key",self.key.to_pem, tmpdir)
        set_param("ssl.crt",self.certificate.to_pem, tmpdir)
        set_param("ssl.csr",self.request.to_pem, tmpdir) if self.request

        set_param("ssl.bundle",self.bundle.map(&:to_pem).join("\n"), tmpdir) if self.bundle and !self.bundle.empty?
        set_param("ssl.combined", combined.map(&:to_pem).join("\n"), tmpdir)

        FileUtils.mv(tmpdir, self.directory)

        self.directory
      end

    end

  end

end
