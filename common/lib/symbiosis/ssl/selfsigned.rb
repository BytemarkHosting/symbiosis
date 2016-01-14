require 'symbiosis/ssl'
require 'symbiosis/ssl/certificate_set'
require 'symbiosis/domain'
require 'symbiosis/domain/ssl'
require 'symbiosis/utils'
require 'etc'
require 'time'

module Symbiosis

  class SSL

    class SelfSigned < CertificateSet

      include Symbiosis::Utils

      attr_reader :domain

      def initialize(domain, directory = nil)
        super
        @names  = ([domain.name] + domain.aliases).uniq
        @config = {:rsa_key_size => nil, :lifetime => nil}
        @rsa_key = nil
        @config_dirs = []
      end

      #
      # This returns a list of configuration directories.
      #
      # TODO: This is probably a site-wide thing.
      #
      def config_dirs
        return @config_dirs unless @config_dirs.empty?

        provider = self.class.to_s.split("::").last.downcase

        #
        # This first path is the default one that gets created.
        #
        paths = [ File.join(self.domain.config_dir, "ssl", provider) ]

        begin
          user = Etc.getpwuid(self.domain.uid)
          paths << File.join(user.dir,".symbiosis", "ssl", provider)
        rescue ArgumentError
          # do nothing
        end

        paths << "/etc/symbiosis/ssl/#{provider}"

        @config_dirs = paths.reject{|p| !File.directory?(p) }

        if @config_dirs.empty?
          mkdir_p(paths.first, {:uid => self.domain.uid, :gid => self.domain.gid})
          @config_dirs << paths.first
        end

        @config_dirs
      end

      def config_dir
        File.join(self.config_dirs.first, self.domain.name)
      end

      #
      # Reads and returns the LetsEncrypt configuration
      #
      def config
        return @config unless @config.values.compact.empty?

        @config.each do |param, value|
          @config[param] = get_param_with_dir_stack(param.to_s, self.config_dirs)
        end

        @config
      end

      #
      # This returns the rsa_key_size.  Defaults to 2048.
      #
      def rsa_key_size
        return @config[:rsa_key_size] if @config[:rsa_key_size].is_a?(Integer) and @config[:rsa_key_size] >= 2048

        rsa_key_size = nil

        if self.config[:rsa_key_size].is_a?(String)
          begin
            rsa_key_size = Integer(self.config[:rsa_key_size])
          rescue ArgumentError
            # do nothing, but maybe we should warn.
          end
        end

        #
        # Default to 2048
        #
        if !rsa_key_size.is_a?(Integer) or rsa_key_size <= 2048
          rsa_key_size = 2048
        end

        @config[:rsa_key_size] = rsa_key_size
      end

      def lifetime
        return @config[:lifetime] if @config[:lifetime].is_a?(Integer) and @config[:lifetime] > 0

        lifetime = nil

        if self.config[:lifetime].is_a?(String)
          begin
            lifetime = Integer(self.config[:lifetime])
          rescue ArgumentError
            # do nothing, but maybe we should warn.
          end
        end

        #
        # Default to 365
        #
        if !lifetime.is_a?(Integer) or lifetime < 1
          lifetime = 365
        end

        @config[:lifetime] = lifetime
      end

      def rsa_key
        return @rsa_key if @rsa_key.is_a?(OpenSSL::PKey::RSA)

        #
        # Generate our expire our request, and generate the key.
        #
        @request = nil
        @rsa_key = OpenSSL::PKey::RSA.new(self.rsa_key_size)
      end

      alias :key :rsa_key

      def register; true ; end
      def registered?; true ; end

      #
      # Verifies all the names for a domain
      #
      def verify(names = @names)
        names.map do |name|
          self.verify_name(name)
        end.all?
      end

      alias :verified? :verify

      #
      # Verifies an individual name.  For self-signed certificates this always
      # returns true.
      #
      def verify_name(name)
        true
      end

      def request(key = self.key, verify_names = true)
        return @request if @request.is_a?(OpenSSL::X509::Request)

        @certificate = nil

        #
        # Here's the request.
        #
        request = OpenSSL::X509::Request.new
        request.public_key = key.public_key

        #
        # Stick the domain name in
        #
        request.subject = OpenSSL::X509::Name.new([
          ['CN', self.domain.name, OpenSSL::ASN1::UTF8STRING]
        ])

        #
        # Add in our X509v3 extensions.
        #
        exts = []
        ef = OpenSSL::X509::ExtensionFactory.new

        names = ([self.domain.name] + self.domain.aliases).uniq

        if verify_names
          names = @names.reject{|name| !self.verify_name(name)}
        else
          names = @names
        end


        #
        # Use the subjectAltName if one has been given.  This is for SNI, i.e. SSL
        # name-based virtual hosting (ish).
        #
        exts << ef.create_extension(
             "subjectAltName",
             names.collect{|a| "DNS:#{a}" }.join(","),
             false
        )

        #
        # Wrap our extension in a Set and Sequence
        #
        attrval = OpenSSL::ASN1::Set([OpenSSL::ASN1::Sequence(exts)])
        request.add_attribute(OpenSSL::X509::Attribute.new("extReq", attrval))
        request.sign(key, OpenSSL::Digest::SHA256.new)

        @request = request
      end

      def verify_and_request_certificate!
        self.request(self.key, true)
      end

      #
      # Returns the signed X509 certificate for the request.
      #
      def certificate(request = self.request, key = self.key, options = {})
        return @certificate if @certificate.is_a?(OpenSSL::X509::Certificate)

        # And then the certificate
        crt            = OpenSSL::X509::Certificate.new
        crt.subject    = request.subject
        crt.issuer     = request.subject

        crt.public_key = request.public_key
        crt.not_before = options[:not_before] || Time.now
        crt.not_after  = options[:not_after]  || (crt.not_before + self.lifetime*86400)
        #
        # Make sure we increment the serial for each regeneration, to make sure
        # there are differences when regenerating a certificate for a new domain.
        #
        crt.serial     = Time.now.to_i
        crt.version    = 2

        #
        # Add in our X509v3 extensions.
        #
        ef = OpenSSL::X509::ExtensionFactory.new
        ef.subject_certificate = crt
        ef.issuer_certificate  = crt

        crt.extensions = [
          ef.create_extension("basicConstraints","CA:FALSE", true),
          ef.create_extension("subjectKeyIdentifier", "hash")
#          ef.create_extension("authorityKeyIdentifier", "keyid:always,issuer:always")
        ]

        #
        # Add subjectAltName extension
        #
        ext_req = request.attributes.find{|a| a.oid == "extReq" }
        ext_req.value.first.value.each do |ext|
          this_ext = OpenSSL::X509::Extension.new(ext)
          next unless this_ext.oid == "subjectAltName"
          crt.add_extension(this_ext)
        end

        crt.sign(key, OpenSSL::Digest::SHA256.new)

        @certificate = crt
      end

      #
      # Returns the CA bundle as an array
      #
      def bundle(request = self.request)
        []
      end

    end

    PROVIDERS << SelfSigned

  end

end


