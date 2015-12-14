require 'symbiosis/domain'
require 'symbiosis/ssl'
require 'symbiosis/utils'
require 'openssl'
require 'tmpdir'
require 'erb'

module Symbiosis

  class SSL

    class Set

      include Comparable
      include Symbiosis::Utils

      attr_reader :directory, :domain, :name

      def initialize(domain, directory)
        raise Errno::ENOENT.new directory unless File.exist?(directory)
        raise Errno::ENOTDIR.new directory unless File.directory?(directory)

        @directory = directory
        @domain    = domain

        if @directory == @domain.config_dir
          @name = "legacy"
        else
          @name = File.basename(@directory)
        end
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

        return OpenSSL::X509::Certificate.new(data)

      rescue OpenSSL::OpenSSLError => err
        warn "\tCould not parse data in #{self.certificate_file}: #{err}"
        return nil
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

        return OpenSSL::PKey::RSA.new(data)

      rescue OpenSSL::OpenSSLError => err
        warn "\tCould not parse data in #{self.key_file}: #{err}"
        return nil 
      end

      #
      # Returns the certificate chain filename, if one exists, or one has been
      # set, or nil if nothing could be found.
      #
      def certificate_chain_file
        if get_param("ssl.bundle", self.directory)
          File.join( self.directory,"ssl.bundle" )
        else
          nil
        end
      end

      alias bundle_file certificate_chain_file

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
           warn "\tUnable to add chain file to the store."
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
            warn "\t#{msg}" if $VERBOSE
          end
        end

        # Check that the certificate is current
        #
        #
        if certificate.not_before > Time.now
          msg = "The certificate for #{@domain.name} is not valid yet."
          if strict_checking
            raise OpenSSL::X509::CertificateError, msg
          else
            warn "\t#{msg}" if $VERBOSE
          end
        end

        if certificate.not_after < Time.now
          msg = "The certificate for #{@domain.name} has expired."
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
          raise OpenSSL::X509::CertificateError, "The certificate's public key does not match the supplied private key for #{@domain.name}."
        end

        #
        # Now check the signature.
        #
        # First see if we can verify it using our own private key, i.e. the
        # certificate is self-signed.
        #
        if certificate.verify(key)
          puts "\tUsing a self-signed certificate for #{@domain.name}." if $VERBOSE

        #
        # Otherwise see if we can verify it using the certificate store,
        # including any bundle that has been uploaded.
        #
        elsif store.is_a?(OpenSSL::X509::Store) and store.verify(certificate)
          puts "\tUsing certificate signed by #{certificate.issuer.to_s} for #{@domain.name}" if $VERBOSE

        #
        # If we can't verify -- raise an error if strict_checking is enabled
        #
        else
          msg =  "Certificate signature does not verify for #{@domain.name} -- maybe a bundle is missing?"
          if strict_checking
            raise OpenSSL::X509::CertificateError, msg
          else
            warn "\t#{msg}" if $VERBOSE
          end
        end

        true
      end

    end

  end

end

