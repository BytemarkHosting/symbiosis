require 'symbiosis/ssl'
require 'symbiosis/domain'
require 'symbiosis/domain/ssl'
begin
  require 'symbiosis/domain/http'
rescue LoadError
   # Do nothing
end

require 'symbiosis/host'
require 'symbiosis/utils'
require 'time'
require 'acme-client'


module Symbiosis

  class SSL

    class LetsEncrypt

      include Symbiosis::Utils

      ENDPOINT = "https://acme-v01.api.letsencrypt.org/directory"

      attr_reader :config, :domain

      def initialize(domain)
        @domain = domain
        @prefix = domain.prefix
        @names  = ([domain.name] + domain.aliases).uniq
        @config = {}
      end

      #
      # Returns the client instance.
      #
      def client
        @client ||= Acme::Client.new(private_key: self.account_key, endpoint: self.endpoint)
      end

      #
      # This returns a list of configuration directories.
      #
      # TODO: This is probably a site-wide thing.
      #
      def config_dirs
        return @config_dirs if @config_dirs        

        paths = [ File.join(self.domain.config_dir, "ssl", "letsencrypt") ]

        #
        # This last path is the default one that gets created.
        #
        if ENV["HOME"]
          paths << File.join(ENV["HOME"],".symbiosis", "ssl", "letsencrypt")
        end
        
        paths << "/etc/symbiosis/config/ssl/letsencrypt"

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
        return @config unless @config.empty?

        @config = {:email => nil, :server => nil, :rsa_key_size => nil, :docroot => nil, :account_key => nil}

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

      #
      # Returns the account key.  If one has not been set, it generates and
      # writes it to the configuration directory.
      #
      def account_key
        return @config[:account_key] if @config[:account_key].is_a?(OpenSSL::PKey::RSA)

        if self.config[:account_key].is_a? String
          account_key = OpenSSL::PKey::RSA.new(self.config[:account_key])
        else
          account_key = OpenSSL::PKey::RSA.new(self.rsa_key_size)
          set_param( "account_key", account_key.to_pem, self.config_dirs.first, :mode => 0600, :uid => @domain.uid, :gid => @domain.gid)
        end

        @config[:account_key] = account_key
      end

      #
      # Returns the document root for the HTTP01 challenge
      # 
      def docroot
        return self.config[:docroot] if self.config[:docroot].is_a?(String) and File.directory?(self.config[:docroot])

        #
        # If symbiosis-http is installed, we use htdocs dir, otherwise default to public/htdocs.
        #
        if self.domain.respond_to?(:htdocs_dir)
          @config[:docroot] = self.domain.htdocs_dir
        else
          @config[:docroot] = File.join(domain.directory, "public", "htdocs")
        end

        @config[:docroot]
      end

      #
      # Returns the account's email address, defaulting to root@fqdn if nothing set.
      #
      def email
        return self.config[:email] if self.config[:email].is_a?(String)

        @config[:email] = "root@"+Symbiosis::Host.fqdn
      end

      #
      # Returns the default endpoint, defaulting to the live endpoint
      #
      def endpoint
        return self.config[:endpoint] if self.config[:endpoint].is_a?(String)

        @config[:endpoint] = ENDPOINT
      end

      #
      # Register the account RSA kay with the letsencrypt server
      #
      def register
        #
        # Send the key to the server.
        #
        registration = self.client.register(contact: 'mailto:'+self.email)

        # 
        # Should probably check we accept the terms.
        #
        registration.agree_terms

        true
      end

      alias :registered? :register

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
      # This does the authorization.  Returns true if the verification succeeds.
      #
      def verify_name(name)
        # 
        # Set up the authorisation for the http01 challenge
        #
        authorisation = self.client.authorize(domain: name)
        challenge     = authorisation.http01

        mkdir_p(File.join(self.docroot, File.dirname(challenge.filename)), 
          :uid => @domain.uid, :gid => @domain.gid)

        set_param(challenge.file_content,
          File.basename(challenge.filename), 
          File.join(self.docroot, File.dirname(challenge.filename)), 
          :uid => @domain.uid, :gid => @domain.gid)

        if challenge.request_verification
          20.times do
            sleep(0.5)
            break if challenge.verify_status == "valid"
          end

          challenge.verify_status == "valid"
        else
          false
        end
      end

      def rsa_key
        return @rsa_key if @rsa_key.is_a?(OpenSSL::PKey::RSA)

        #
        # Generate our expire our request, and generate the key.
        #
        @request     = nil
        @rsa_key = OpenSSL::PKey::RSA.new(self.rsa_key_size)
      end

      alias :key :rsa_key

      def request(key = self.key, verify_names = true)
        return @request if @request.is_a?(OpenSSL::X509::Request)

        @acme_certificate = nil

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

        #
        # OK here we want to verify each domain before adding them to the cert
        #
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

      alias :verify_and_request_certificate! :request

      def acme_certificate(request = self.request)
        return @acme_certificate if @acme_certificate.is_a?(Acme::Certificate)

        acme_certificate = client.new_certificate(request)

        if acme_certificate.is_a?(Acme::Certificate)
          @acme_certificate = acme_certificate 
        else
          @acme_certificate = nil
        end

        @acme_certificate
      end

      #
      # Returns the signed X509 certificate for the request.
      #
      def certificate(request = self.request)
        if self.acme_certificate(request).is_a?(Acme::Certificate)
          self.acme_certificate.x509
        else
          nil
        end
      end


      #
      # Returns the CA bundle as an array
      #
      def bundle(request = self.request)
        if self.acme_certificate(request).is_a?(Acme::Certificate)
          self.acme_certificate.x509_chain
        else
          []
        end
      end

    end

    PROVIDERS << LetsEncrypt

  end

end


