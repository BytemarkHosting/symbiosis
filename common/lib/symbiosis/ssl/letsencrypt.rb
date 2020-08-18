# Updated in 2019 for Sympl (https://sympl.host) to support ACMEv02 Let's Encrypt API
#   Sympl is a fork of Symbiosis under active development, with support for current Debian.
#   The Sympl Project is supported by Mythic Beasts (mythic-beasts.com)
#   Source: https://gitlab.mythic-beasts.com/sympl/sympl/-/blob/buster/core/lib/symbiosis/ssl/letsencrypt.rb
#
# This version back-ported to Symbiosis in Feb 2020.
#
# Original version copyright 2016 Bytemark Hosting.

require 'symbiosis/ssl'
require 'symbiosis/ssl/selfsigned'
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

      ENDPOINT = "https://acme-v02.api.letsencrypt.org/directory"

      def initialize(domain, endpoint = nil)
        super
        @config = {:email => nil, :endpoint => nil, :rsa_key_size => nil, :docroot => nil, :account_key => nil}
        @verified_names = {};
      end

      #
      # Returns the client instance.
      #
      def client
        @client ||= Acme::Client.new(private_key: self.account_key, directory: self.endpoint)
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
        unless self.config[:email].is_a?(String)
          @config[:email] = "root@"+Symbiosis::Host.fqdn
        end

        if @config[:email] =~ /([^\.@%!\/\|\s][^@%!\/\|\s]*@[a-z0-9\.-]+)/i
          @config[:email] = $1
        else
          puts "\tAddress #{@config[:email].inspect} looks wrong.  Using default" if $VERBOSE
          @config[:email] = "root@"+Symbiosis::Host.fqdn
        end

        return self.config[:email]
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
        registration = self.client.new_account(contact: 'mailto:'+self.email, terms_of_service_agreed: true)
        puts "\tCreated new account with email address: "+self.email if $VERBOSE
        puts "KeyID is: "+registration.kid if $DEBUG

        return true
      end

      #
      # Tests to see if we're registered by doing a pre-emptive authorize
      # request.
      #
      def registered?
        puts "checking registration for #{self.domain.name}," if $DEBUG

        kid = client.kid

        puts "checking for key" if $DEBUG
        puts "client.kid is #{kid}" if $DEBUG

        order = self.client.new_order(identifiers: self.domain.name)
        authorisation = order.authorizations.first
        challenge = authorisation.http

        #do_with_nonce_debounce{ self.client.authorization(url: self.domain.name) }
        puts 'authorized' if $DEBUG
        return true
      rescue Acme::Client::Error::Unauthorized
        puts 'not authorised' if $DEBUG
        return false
      rescue Acme::Client::Error::RejectedIdentifier
        puts 'authorized, but invalid name?' if $DEBUG
        return false
      rescue Acme::Client::Error::AccountDoesNotExist
        puts 'account does not exist' if $DEBUG
        return false
      end

      #
      # This does the authorization.  Returns true if the verification succeeds.
      #
      def verify_name(name)
        return @verified_names[name] if @verified_names.include?(name)

        #
        # Set up the authorisation for the http01 challenge
        #

        order = self.client.new_order(identifiers: name)
        authorisation = order.authorizations.first
        challenge = authorisation.http

        challenge_directory = File.join(self.docroot, File.dirname(challenge.filename))

        mkdir_p(challenge_directory)

        set_param(File.basename(challenge.filename), challenge.file_content, challenge_directory)

        vs = nil # Record the verify status

        if do_with_nonce_debounce{ challenge.request_validation }
          puts "\tRequesting verification for #{name} from #{endpoint}" if $VERBOSE

          60.times do
            vs = do_with_nonce_debounce { challenge.status }
            break unless vs == "pending"
            sleep(1)
            challenge.reload
          end
        end

        set_param(File.basename(challenge.filename), false, challenge_directory) unless $DEBUG

        if vs == "valid"
          puts "\tSuccessfully verified #{name}" if $VERBOSE
          @verified_names[name] = true
        else
          if $VERBOSE
            puts "\t!! Unable to verify #{name} (status: #{vs})"
            puts "\t!! Check http://#{name}/#{challenge.filename} works."
          end
          @verified_names[name] = false
        end
        return @verified_names[name]
      end

      def acme_certificate(request = self.request)
        return @certificate if not @certificate.nil?

        raise ArgumentError, "Invalid certificate request" unless request.is_a?(OpenSSL::X509::Request)

        puts "csr=#{request}" if $DEBUG

#        acme_certificate = do_with_nonce_debounce{ client.new_certificate(request) }

        names = @names.select { |name| self.verify_name(name) }
        puts "names=#{names.join(', ')}" if $DEBUG
        order = client.new_order(identifiers: names)
        authorization = order.authorizations.first
        challenge = authorization.http

        order.finalize(csr: request)

        while order.status == 'processing'
          sleep(1)
          puts '.'
          challenge.reload
        end

        acme_certificate = order.certificate

        puts "certificate=#{acme_certificate}" if $DEBUG

        #if acme_certificate.is_a?(OpenSSL::X509::Certificate)
        if acme_certificate.include? "-----BEGIN CERTIFICATE-----"
          puts "That looks like a real cert!" if $DEBUG
          @certificate = acme_certificate
        else
          puts "That's aparently not a cert?" if $DEBUG
          @certificate = nil
        end

        @certificate
      end

      #
      # Returns the signed X509 certificate for the request.
      #
      def certificate(request = self.request)
#       if self.acme_certificate(request).is_a?(Acme::Client::Certificate)
        if self.acme_certificate(request).include? "-----BEGIN CERTIFICATE-----"
          #self.acme_certificate(request)
          OpenSSL::X509::Certificate.new(self.acme_certificate(request).split("\n\n")[0])
        else
          nil
        end
      end

      #
      # Returns the CA bundle as an array
      #
      def bundle(request = self.request)
#       if self.acme_certificate(request).is_a?(Acme::Client::Certificate)
        if self.acme_certificate(request).include? "-----BEGIN CERTIFICATE-----"
#          self.acme_certificate.x509_chain
          self.acme_certificate(request).split("\n\n")[1..-1].map { |cert| OpenSSL::X509::Certificate.new(cert) }
        else
          []
        end
      end

      #
      # The letsencrypt servers sometimes complain about bad replay nonces.
      # The client should retry a reasonable number of times, so this is our
      # wrapper to retry any request up to 5 times.
      #
      # https://community.letsencrypt.org/t/getting-the-client-sent-an-unacceptable-anti-replay-nonce/9172
      # https://github.com/letsencrypt/boulder/issues/1217
      #
      def do_with_nonce_debounce(&block)
        retries = 0

        begin
          yield

        rescue Acme::Client::Error::BadNonce => err

          if retries < 5
            retries += 1
            sleep 0.5 # Don't hammer the servers too quickly
            retry
          end

          #
          # Ugh, something is going wrong.  Lets bail out.
          #
          raise err

        end

      end

    end

    PROVIDERS << LetsEncrypt

  end

end

