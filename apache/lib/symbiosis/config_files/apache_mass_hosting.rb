require 'symbiosis/config_files/apache_ssl'

module Symbiosis
  module ConfigFiles
    class ApacheMassHosting < Symbiosis::ConfigFiles::ApacheSSL

      #
      # Return all the IPs as apache-compatible strings.
      #
      def ips
        [Symbiosis::Host.primary_ipv4, Symbiosis::Host.primary_ipv6].compact.collect do |ip|
          if ip.ipv6?
            "["+ip.to_s+"]"
          elsif ip.ipv4?
            ip.to_s
          end
        end
      end

      #
      # Returns the SSLCertificateFile snippet
      #
      def ssl_certificate_file
        "SSLCertificateFile /etc/ssl/ssl.crt"
      end
      
      #
      # Returns the SSLCertificateKeyFile snippet, as needed.
      #
      def ssl_certificate_key_file
        if File.exists?("/etc/ssl/ssl.key")
          "SSLCertificateKeyFile /etc/ssl/ssl.key"
        else
          ""
        end
      end

      #
      # Returns the SSLCertificateChainFile snippet, as needed.
      #
      def ssl_certificate_chain_file
        if File.exists?("/etc/ssl/ssl.bundle")
          "SSLCertificateChainFile /etc/ssl/ssl.bundle"
        else
          ""
        end
      end
    end
  end
end


