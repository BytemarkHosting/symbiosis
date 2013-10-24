require 'symbiosis/domain'
require 'openssl'
require 'base64'
require 'socket'
require 'erb'

module Symbiosis

  class Domain

    #
    # Returns true if DKIM public and private keys are available, and match.
    #
    def dkim_enabled?
      self.dkim_selector and self.dkim_key
    end

    #
    # Returns the domains SSL key as an OpenSSL::PKey::RSA object, or nil if no
    # key file could be found.
    #
    def dkim_key
      return @dkim_key unless @dkim_key.nil?
      key = get_param("dkim.key", self.config_dir)

      @dkim_key = if key.is_a?(String)
        begin
          OpenSSL::PKey::RSA.new(key)
        rescue OpenSSL::OpenSSLError => err
          nil
        end
      else
        nil
      end
    end

    #
    # Returns the domains SSL key as an OpenSSL::PKey::RSA object, or nil if no
    # key file could be found.
    #
    def dkim_key=(k)
      raise ArgumentError, "key is not an OpenSSL::PKey::RSA" unless k.is_a?(OpenSSL::PKey::RSA)
      @dkim_key = k
    end

    #
    # Returns the public part of the DKIM key, or nil of no DKIM key is available
    #
    def dkim_public_key
      if self.dkim_key.is_a?(OpenSSL::PKey::RSA)
        self.dkim_key.public_key
      else
        nil
      end
    end

    #
    # Generates a DKIM private key.
    #
    def generate_dkim_key
      self.dkim_key = OpenSSL::PKey::RSA.new(1536)
    end

    #
    # This returns the dkim selector, stored in config/dkim.  If that file is
    # empty, the first component of either /etc/mailname, /etc/hostname, or the
    # hostname returned by the hostname(1) command is used.
    #
    def dkim_selector
      selector = get_param("dkim", self.config_dir)
      selector_regex = /\b([a-z0-9-]+(\.[a-z0-9-]+)*)\b/i

      @dkim_selector = if selector.is_a?(String) and selector =~ selector_regex
        $1.to_s
  
      elsif selector == false
        nil

      else
        #
        # Here we mirror what exim4 does when it works out primary_hostname.
        #
        # "This variable contains the value set by primary_hostname in the
        #  configuration file, or read by the uname() function. If uname()
        #  returns a single-component name, Exim calls gethostbyname() (or
        #  getipnodebyname() where available) in an attempt to acquire a fully
        #  qualified host name."
        #
        # Try /proc/sys/kernel/hostname (which mirrors what uname returns)
        #
        hostname = get_param("hostname", '/proc/sys/kernel')

        hostname = ""  unless hostname.is_a?(String) 
        
        hostname.chomp!

        unless hostname.empty? or !hostname.include?(".")
          begin
            hostname = Socket.gethostbyname(hostname).first
          rescue SocketError
            hostname = ""
          end
        end

        #
        # Default to "default" if the hostname doesn't match the regex.  This
        # should never happen (I don't think!).
        #
        hostname = "default" unless hostname =~ selector_regex
        hostname
      end
    end

    #
    # This returns the Base64 encoded public DKIM key for use in a TXT record.
    #
    def dkim_public_key_b64
      #
      # Ruby 1.8 uses a different output format for the DER encoded public key
      # to both OpenSSL and Ruby1.9+, so we have to construct the correct
      # format ourselves.
      #
      der_key = if RUBY_VERSION =~ /^1\.8/ 
        OpenSSL::ASN1::Sequence.new([
          OpenSSL::ASN1::Sequence.new([
            OpenSSL::ASN1::ObjectId.new("rsaEncryption"),
            OpenSSL::ASN1::Null.new(nil)
          ]),
          OpenSSL::ASN1::BitString.new(self.dkim_public_key.to_der)
        ]).to_der
      else
        self.dkim_public_key.to_der
      end

      Base64::encode64(der_key).gsub("\n","")
    end
  end
end
