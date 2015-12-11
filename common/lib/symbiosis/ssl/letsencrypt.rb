require 'symbiosis/ssl'
require 'symbiosis/ssl/selfsigned'
require 'symbiosis/domain'
require 'symbiosis/domain/ssl'
require 'symbiosis/host'
require 'symbiosis/utils'
require 'time'
require 'acme-client'

begin
  require 'symbiosis/domain/http'
rescue LoadError
   # Do nothing
end

module Symbiosis

  class SSL

    class LetsEncrypt < Symbiosis::SSL::SelfSigned

      ENDPOINT = "https://acme-v01.api.letsencrypt.org/directory"

      def initialize(domain)
        super
        @config = {:email => nil, :server => nil, :rsa_key_size => nil, :docroot => nil, :account_key => nil}
      end

      #
      # Returns the client instance.
      #
      def client
        @client ||= Acme::Client.new(private_key: self.account_key, endpoint: self.endpoint)
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
          set_param( "account_key", account_key.to_pem, self.config_dirs.first, :mode => 0600)
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
      # This does the authorization.  Returns true if the verification succeeds.
      #
      def verify_name(name)
        # 
        # Set up the authorisation for the http01 challenge
        #
        authorisation = self.client.authorize(domain: name)
        challenge     = authorisation.http01

        mkdir_p(File.join(self.docroot, File.dirname(challenge.filename)))

        set_param(challenge.file_content,
          File.basename(challenge.filename), 
          File.join(self.docroot, File.dirname(challenge.filename)))

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

      def acme_certificate(request = self.request)
        return @certificate if @certificate.is_a?(Acme::Certificate)

        acme_certificate = client.new_certificate(request)

        if acme_certificate.is_a?(Acme::Certificate)
          @certificate = acme_certificate 
        else
          @certificate = nil
        end

        @certificate
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


