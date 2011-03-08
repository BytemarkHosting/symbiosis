#!/usr/bin/ruby 

# OK we're running this test locally
unless File.dirname( File.expand_path( __FILE__ ) ) == "/etc/symbiosis/test.d"
  ["../lib", "../../test/lib" ].each do |d|
    if File.directory?(d) 
      $: << d
    else
      raise Errno::ENOENT, d
    end
  end
end

require 'test/unit'
require "tempfile"
require 'etc'
require 'pp'
require 'symbiosis/ssl_configuration'
require 'symbiosis/test/http'

TMP_PATH = File.join("/tmp", "#{__FILE__}.#{$$}")

module Symbiosis 
  module Test
    class Http
      def directory
        File.join(TMP_PATH, "srv", @name)
      end
    end
  end
end

class SSLConfigTest < Test::Unit::TestCase

  @@serial=0

  def setup
    @domain = Symbiosis::Test::Http.new
    @domain.user  = Etc.getpwuid.name
    @domain.group = Etc.getgrgid(Etc.getpwuid.gid).name
    @domain.create

    @ssl = Symbiosis::SSLConfiguration.new(@domain.name)
    @ssl.root_path = TMP_PATH

    #
    # Copy some SSL certs over
    #
    FileUtils.mkdir_p(@domain.directory+"/config")

  end

  def teardown
    @domain.destroy unless $DEBUG
    FileUtils.rm_rf TMP_PATH unless $DEBUG
  end

  #####
  #
  # Helper methods
  #
  #####

  #
  # Returns a private key
  #
  def do_generate_key
    # This is a very short key!
    OpenSSL::PKey::RSA.new(512)
  end

  #
  # Returns a new certificate given a key
  #
  def do_generate_crt(domain, key=nil, ca_cert=nil, ca_key=nil)
    #
    # Generate a key if none has been specified
    #
    key = do_generate_key if key.nil?

    #
    # Check CA key and cert
    #
    if !ca_cert.nil? and !ca_key.nil? and !ca_cert.check_private_key(ca_key)
      warn "CA certificate and key do not match -- not using." 
      ca_cert = ca_key = nil
    end

    # Generate the request 
    csr            = OpenSSL::X509::Request.new
    csr.version    = 0
    csr.subject    = OpenSSL::X509::Name.new( [ ["C","GB"], ["CN", domain]] )
    csr.public_key = key.public_key
    csr.sign( key, OpenSSL::Digest::SHA1.new )

    # And then the certificate
    crt            = OpenSSL::X509::Certificate.new
    crt.subject    = csr.subject

    #
    # Theoretically we could use a CA to sign the cert.
    #
    if ca_cert.nil? or ca_key.nil?
      warn "Not setting the issuer as the CA because the CA key is not set" if !ca_cert.nil? and ca_key.nil?
      crt.issuer    = csr.subject
    else
      crt.issuer   = ca_cert.subject
    end
    crt.public_key = csr.public_key
    crt.not_before = Time.now
    crt.not_after  = Time.now + 60
    #
    # Make sure we increment the serial for each regeneration, to make sure
    # there are differences when regenerating a certificate for a new domain.
    #
    crt.serial     = @@serial
    @@serial += 1
    crt.version    = 1 

    if ca_cert.nil? or ca_key.nil?
      warn "Not signing certificate with CA key because the CA certificate is not set" if ca_cert.nil? and !ca_key.nil?
      crt.sign( key, OpenSSL::Digest::SHA1.new )  
    else
      crt.sign( ca_key, OpenSSL::Digest::SHA1.new )
    end

    crt
  end

  #
  # Returns a key and certificate
  #
  def do_generate_key_and_crt(domain, ca_cert=nil, ca_key=nil)
    key = do_generate_key
    return [key, do_generate_crt(domain, key, ca_cert, ca_key)]
  end

  ####
  #
  # Tests start here.
  #
  #####

  def test_ssl_enabled?
    #
    # This should return true if an IP has been set, and we can find a matching key and cert.
    #
    # Initially no IP or key / cert have been configured.
    #
    assert( !@ssl.ssl_enabled? )

    #
    # Now set an IP.  This should still return false.
    #
    ip = "80.68.88.52"
    File.open(@domain.directory+"/config/ip","w+"){|fh| fh.puts ip}
    assert( !@ssl.ssl_enabled? )

    #
    # Generate a key + cert.  It should now return true.
    #
    key, crt = do_generate_key_and_crt(@domain.name)
    File.open(@domain.directory+"/config/ssl.combined","w+"){|fh| fh.write crt.to_pem+key.to_pem}
    assert( @ssl.ssl_enabled? )
  end

  def test_site_enabled?
    #
    # The site is enabled if the etc/apache2/sites-enabled/domain.ssl exists
    #

  end

  def test_mandatory_ssl?
    #
    # First make sure this responds "false" 
    #
    assert( !@ssl.mandatory_ssl? )

    #
    # Now it should return true
    #
    FileUtils.touch(@domain.directory+"/config/ssl-only")
    assert( @ssl.mandatory_ssl? )
  end

  def test_remove_site

  end

  def test_ip
    #
    # If no IP has been set, it should return nil
    #
    assert_nil( @ssl.ip )

    #
    # Now we set an IP
    #
    ip = "80.68.88.52"
    File.open(@domain.directory+"/config/ip","w+"){|fh| fh.puts ip}
    assert_equal(@ssl.ip, ip)

  end


  def test_certificate
    #
    # Generate a key 
    #
    key, crt = do_generate_key_and_crt(@domain.name)

    #
    # Return nil if no certificate filename has been set
    #
    assert_nil(@ssl.x509_certificate)

    #
    # Now write the file
    #
    File.open(@domain.directory+"/config/ssl.combined","w+"){|fh| fh.write crt.to_pem+key.to_pem}
    @ssl.certificate_file = @domain.directory+"/config/ssl.combined"

    #
    # Now it should read back the combined file correctly
    #
    assert_kind_of(crt.class, @ssl.x509_certificate)
    assert_equal(crt.to_der, @ssl.x509_certificate.to_der)

    #
    # Generate a new certificate
    #
    key, crt = do_generate_key_and_crt(@domain.name)
    #
    # Make sure it doesn't match the last one
    #
    assert_not_equal(crt.to_der, @ssl.x509_certificate.to_der)

    File.open(@domain.directory+"/config/ssl.crt","w+"){|fh| fh.write crt.to_pem}
    @ssl.certificate_file = @domain.directory+"/config/ssl.crt"
    #
    # Now it should read back the individual file correctly
    #
    assert_equal(crt.to_der, @ssl.x509_certificate.to_der)
  end

  #
  # Sh
  #
  def test_key
    #
    # Generate a key and cert
    #
    key, crt = do_generate_key_and_crt(@domain.name)

    #
    # Return nil if no certificate filename has been set
    #
    assert_nil(@ssl.key)

    File.open(@domain.directory+"/config/ssl.combined","w+"){|fh| fh.write crt.to_pem+key.to_pem}
    @ssl.key_file = @domain.directory+"/config/ssl.combined"

    #
    # Now it should read back the combined file correctly
    #
    assert_kind_of(key.class, @ssl.key)
    assert_equal(key.to_der, @ssl.key.to_der)

    #
    # Generate a new key
    #
    key = do_generate_key

    #
    # Make sure it doesn't match the last one
    #
    assert_not_equal(key.to_der, @ssl.key.to_der)

    File.open(@domain.directory+"/config/ssl.key","w+"){|fh| fh.write key.to_pem}
    @ssl.key_file = @domain.directory+"/config/ssl.key"

    assert_equal(key.to_der, @ssl.key.to_der)
  end

  def test_certificate_chain_file
    # TODO: Requires setting up a dummy CA + intermediate bundle.
    #
  end

  def test_certificate_store
    # TODO: Requires setting up a dummy CA + intermediate bundle.
  end

  def test_avilable_certificate_files
    #
    # Generate a key and cert
    #
    key, crt = do_generate_key_and_crt(@domain.name)

    #
    # Write the certificate in various forms
    #
    File.open(@domain.directory+"/config/ssl.combined","w+"){|fh| fh.write crt.to_pem+key.to_pem}
    File.open(@domain.directory+"/config/ssl.key","w+"){|fh| fh.write crt.to_pem+key.to_pem}
    File.open(@domain.directory+"/config/ssl.crt","w+"){|fh| fh.write crt.to_pem}
    File.open(@domain.directory+"/config/ssl.cert","w+"){|fh| fh.write crt.to_pem}
    File.open(@domain.directory+"/config/ssl.pem","w+"){|fh| fh.write crt.to_pem}

    #
    # Combined is preferred
    #
    assert_equal( %w(combined key crt cert pem).collect{|ext| @domain.directory+"/config/ssl."+ext}, 
                   @ssl.available_certificate_files)

    #
    # If a combined file contains a non-matching cert+key, don't return it
    #
    new_key = do_generate_key
    File.open(@domain.directory+"/config/ssl.combined","w+"){|fh| fh.write crt.to_pem + new_key.to_pem}

    assert_equal( %w(key crt cert pem).collect{|ext| @domain.directory+"/config/ssl."+ext},
                  @ssl.available_certificate_files )
  end

  def test_available_keys
    #
    # Generate a key and cert
    #
    key, crt = do_generate_key_and_crt(@domain.name)

    #
    # Write the key to a number of files
    #
    File.open(@domain.directory+"/config/ssl.combined","w+"){|fh| fh.write crt.to_pem+key.to_pem}
    File.open(@domain.directory+"/config/ssl.key","w+"){|fh| fh.write key.to_pem}
    File.open(@domain.directory+"/config/ssl.crt","w+"){|fh| fh.write crt.to_pem}

    #
    # Combined is preferred
    #
    assert_equal( %w(combined key).collect{|ext| @domain.directory+"/config/ssl."+ext}, 
                  @ssl.available_key_files )

    #
    # If a combined file contains a non-matching cert+key, don't return it
    #
    new_key = do_generate_key
    File.open(@domain.directory+"/config/ssl.combined","w+"){|fh| fh.write crt.to_pem + new_key.to_pem}
    assert_equal( [@domain.directory+"/config/ssl.key"], 
                  @ssl.available_key_files )
  end

  def test_find_matching_certificate_and_key
    #
    # Generate a key and cert
    #
    key, crt = do_generate_key_and_crt(@domain.name)

    #
    # If no key and cert are found, nil is returned.
    #
    assert_nil( @ssl.find_matching_certificate_and_key )

    #
    # Initially, the combined cert should contain both the certificate and the key
    #
    File.open(@domain.directory+"/config/ssl.combined","w+"){|fh| fh.write crt.to_pem+key.to_pem}
    File.open(@domain.directory+"/config/ssl.key","w+"){|fh| fh.write crt.to_pem+key.to_pem}
    assert_equal( [@domain.directory+"/config/ssl.combined"]*2, 
                  @ssl.find_matching_certificate_and_key )

    #
    # Now delete that file, and see what comes out.  We expect the key to be first now.
    #
    FileUtils.rm_f(@domain.directory+"/config/ssl.combined")
    assert_equal( [@domain.directory+"/config/ssl.key"]*2,
                  @ssl.find_matching_certificate_and_key )

    #
    # Now recreate a key which is only a key, and see if we get the correct cert returned.
    #
    File.open(@domain.directory+"/config/ssl.key","w+"){|fh| fh.write key.to_pem}
    File.open(@domain.directory+"/config/ssl.crt","w+"){|fh| fh.write crt.to_pem}
    assert_equal( [@domain.directory+"/config/ssl.crt", @domain.directory+"/config/ssl.key"], 
                  @ssl.find_matching_certificate_and_key )

    #
    # Now generate a new key, and corrupt the combined certificate.
    # find_matching_certificate_and_key should now return the separate,
    # matching key and cert.
    #
    new_key = do_generate_key
    File.open(@domain.directory+"/config/ssl.combined","w+"){|fh| fh.write crt.to_pem + new_key.to_pem}
    assert_equal( [@domain.directory+"/config/ssl.crt", @domain.directory+"/config/ssl.key"],
                  @ssl.find_matching_certificate_and_key )

    #
    # Now remove the crt file, leaving the duff combined cert, and the other
    # key.  This should return nil, since the combined file contains the
    # certificate that matches the *separate* key, and a non-matching key,
    # rendering it useless.
    #
    FileUtils.rm_f(@domain.directory+"/config/ssl.crt")
    assert_nil(@ssl.find_matching_certificate_and_key)

  end

  def test_verify_self_signed
    #
    # Generate a key and cert
    #
    key, crt = do_generate_key_and_crt(@domain.name)

    #
    # Write a combined cert
    #
    File.open(@domain.directory+"/config/ssl.combined","w+"){|fh| fh.write crt.to_pem+key.to_pem}

    #
    # Now make sure it verifies OK
    #
    assert_nothing_raised{ @ssl.certificate_file = @domain.directory+"/config/ssl.combined" }
    assert_nothing_raised{ @ssl.key_file         = @domain.directory+"/config/ssl.combined" }

    #
    # This should verify.
    #
    assert_nothing_raised{ @ssl.verify }

    #
    # Generate another key
    #
    new_key = do_generate_key

    #
    # Now write a combined cert with this new key.  This should not verify.
    #
    File.open(@domain.directory+"/config/ssl.combined","w+"){|fh| fh.write crt.to_pem+new_key.to_pem}
    assert_raise(OpenSSL::X509::CertificateError){ @ssl.verify }

    #
    # Now sign the certificate with this new key.  This should cause the verification to fail.
    #
    crt.sign( new_key, OpenSSL::Digest::SHA1.new )
    File.open(@domain.directory+"/config/ssl.combined","w+"){|fh| fh.write crt.to_pem+key.to_pem}
    assert_raise(OpenSSL::X509::CertificateError){ @ssl.verify }

    #
    # Now write a combined cert with the new key.  This should still not
    # verify, as the public key on the certificate will not match the private
    # key, even though we've signed the cert with this new private key.
    #
    File.open(@domain.directory+"/config/ssl.combined","w+"){|fh| fh.write crt.to_pem+new_key.to_pem}
    assert_raise(OpenSSL::X509::CertificateError){ @ssl.verify }
  end

  def test_verify_with_root_ca
    #
    # Use our intermediate CA.
    #
    ca_cert = OpenSSL::X509::Certificate.new(File.read("RootCA/RootCA.crt"))
    ca_key  = OpenSSL::PKey::RSA.new(File.read("RootCA/RootCA.key"))

    #
    # Add the Root CA path
    # 
    @ssl.add_ca_path("./RootCA/")

    #
    # Generate a key and cert
    #
    key = do_generate_key
    crt = do_generate_crt(@domain.name, key, ca_cert, ca_key)

    #
    # Write a combined cert
    #
    File.open(@domain.directory+"/config/ssl.combined","w+"){|fh| fh.write crt.to_pem+key.to_pem}

    #
    # This should verify just fine.
    #
    assert_nothing_raised{ @ssl.certificate_file = @domain.directory+"/config/ssl.combined" }
    assert_nothing_raised{ @ssl.key_file         = @domain.directory+"/config/ssl.combined" }
    assert_nothing_raised{ @ssl.verify }
  end

  def test_verify_with_intermediate_ca
    #
    # Use our intermediate CA.
    #
    ca_cert = OpenSSL::X509::Certificate.new(File.read("IntermediateCA/IntermediateCA.crt"))
    ca_key  = OpenSSL::PKey::RSA.new(File.read("IntermediateCA/IntermediateCA.key"))

    #
    # Add the Root CA path
    # 
    @ssl.add_ca_path("./RootCA/")

    #
    # Generate a key and cert
    #
    key = do_generate_key
    crt = do_generate_crt(@domain.name, key, ca_cert, ca_key)

    #
    # Write a combined cert
    #
    File.open(@domain.directory+"/config/ssl.combined","w+"){|fh| fh.write crt.to_pem+key.to_pem}

    #
    # This should not verify yet, as the bundle hasn't been copied in place.
    #
    assert_nothing_raised{ @ssl.certificate_file = @domain.directory+"/config/ssl.combined" }
    assert_nothing_raised{ @ssl.key_file         = @domain.directory+"/config/ssl.combined" }
    assert_raise(OpenSSL::X509::CertificateError){ @ssl.verify }

    #
    # Now copy the bundle in place
    #
    FileUtils.cp("IntermediateCA/IntermediateCA.crt",@domain.directory+"/config/ssl.bundle")

    #
    # Now it should verify just fine.
    #
    assert_nothing_raised{ @ssl.verify }
  end

  def test_configuration
    #
    # Set the IP address
    #
    ip = "80.68.88.52"
    File.open(@domain.directory+"/config/ip","w+"){|fh| fh.puts ip}

    %w(sites-enabled sites-available).each do |d|
      FileUtils.mkdir_p(@ssl.apache_dir+"/"+d)
    end

    #
    # Generate a key
    #
    key = do_generate_key
    #
    # Generate a certificate
    #
    crt = do_generate_crt(@domain.name, key)

    #
    # Now we add a bundle
    #
    ca_cert = OpenSSL::X509::Certificate.new(File.read("RootCA/RootCA.crt"))
    ca_key  = OpenSSL::PKey::RSA.new(File.read("RootCA/RootCA.key"))
    bundle_crt = do_generate_crt(@domain.name, key, ca_cert, ca_key)

    test_cases = {
     "combined" => {"combined" => crt.to_pem+key.to_pem},
     "separate" => {"key" => key.to_pem, "crt" => crt.to_pem},
     "separate with bundle" => {"key" => key.to_pem, "crt" => bundle_crt.to_pem, "bundle" => ca_cert.to_pem},
     "combined with bundle" => {"combined" => key.to_pem + bundle_crt.to_pem, "bundle" => ca_cert.to_pem}
    }

    #
    #
    # For each of the templates, run the test.
    #
    configs = ["../apache.d/ssl.template.erb"] +  Dir.glob("apache.d/*.erb")
    raise "cannot test templates because none exist" unless configs.length > 0

    configs.each do |template|
      #
      # Run each of the test cases
      #

      test_cases.each do |test_case, files|
        [true, false].each do |mandatory_ssl|
          #
          # Write each of the test files
          #
          files.each do |ext, contents|
            File.open(@domain.directory+"/config/ssl.#{ext}", "w+"){|fh| fh.write contents}
          end

          #
          # Make sure we can handle mandatory SSL
          #
          FileUtils.touch(@domain.directory+"/config/ssl-only") if mandatory_ssl

          #
          # Find a matching key and certificate
          #
          @ssl.certificate_file, @ssl.key_file = @ssl.find_matching_certificate_and_key

          assert_nothing_raised{ @ssl.verify }

          snippet = nil

          #
          # Form the configuration snippet
          #
          assert_nothing_raised("Could not interpolate for #{template} nad #{test_case}"){ snippet = @ssl.config_snippet(template)} 

          #
          # Test snippet for essential lines
          #
          assert_match(/NameVirtualHost\s+#{ip}:80/,  snippet)
          assert_match(/NameVirtualHost\s+#{ip}:443/, snippet)
          assert_match(/<VirtualHost\s+#{ip}:80>/,    snippet)
          assert_match(/<VirtualHost\s+#{ip}:443>/,   snippet)
          
          #
          # Make sure both a cert and key are used when needed
          #
          if files.has_key?("crt") or files.has_key?("key") 
            assert_match(/^\s*SSLCertificateFile\s+#{@domain.directory}\/config\/ssl\.crt/,    snippet)
            assert_match(/^\s*SSLCertificateKeyFile\s+#{@domain.directory}\/config\/ssl\.key/, snippet)
          end

          #
          # Make sure there is just a certificate file when a combined key/cert is used
          #
          if files.has_key?("combined")
            assert_match(/^\s*SSLCertificateFile\s+#{@domain.directory}\/config\/ssl\.combined/, snippet) 
            assert_no_match(/^\s*SSLCertificateKeyFile\s+/, snippet)
          end

          #
          # Make sure the bundle lines are there if a bundle is configured.
          #
          if files.has_key?("bundle")
            assert_match(/^\s*SSLCertificateChainFile\s+#{@domain.directory}\/config\/ssl\.bundle/, snippet)
          else
            assert_no_match(/^\s*SSLCertificateChainFile\s+/, snippet)
          end

          #
          # If mandatory SSL is switched on, then make sure there is a redirect in place.
          #
          if mandatory_ssl
            assert_match(/^\s*Redirect \/ https:\/\/#{@domain.name}/, snippet)
          end
  
          #
          # Write the snippet
          #
          assert_nothing_raised("Could not write configuration for #{template} and #{test_case}"){ @ssl.write_configuration(snippet) }

          #
          # Make sure Apache is happy with it.
          #
          assert(@ssl.configuration_ok?, "Apache2 rejected configuration for #{template} and #{test_case}")

          #
          # Clean up
          #
          files.keys.each do |ext|
            FileUtils.rm(@domain.directory+"/config/ssl.#{ext}")
          end
          FileUtils.rm(@domain.directory+"/config/ssl-only") if mandatory_ssl

        end
      end
    end
  end

  def test_outdated?
    #
    # The config snippet is out of date if
    #
    #  (a) the IP file has changed
    #  (b) any of the SSL files have changed.
    #
    #
    # TODO
  end

  def test_changed?
    #
    # A file is deemed changed if one of 
    #
    # (a) The automatically generated checksum is different from the checksum of the file
    # (b) There is now big warning saying that changes will be overwritten
    #
    # are true.

    test_apache_config =<<EOF
#
# This is a pretend configuration file, that is complete bunkum.
#
#
<Location /:412>
  SomeApacheNonsense on
  OtherApacheNonsesn off
  SiteName testything.com
  Blah yes
  Nonsense certainly
</Location>
EOF
    checksum_line = "# Checksum MD5 "+OpenSSL::Digest::MD5.new(test_apache_config).hexdigest

    FileUtils.mkdir_p(File.dirname(@ssl.sites_available_file))
    File.open(@ssl.sites_available_file, "w+"){ |fh| fh.puts test_apache_config  }

    # This initial config does not contain the big warning, or an MD5 sum, so it should be seen as "changed".
    #
    assert(@ssl.changed?)

    #
    # OK, now add the MD5 sum, and magically the file should appear as unedited..
    #
    File.open(@ssl.sites_available_file, "a"){ |fh| fh.puts checksum_line  }
    assert(!@ssl.changed?)

    #
    # OK now we'll edit the file, keeping the checksum the same.
    #
    edited_apache_config = test_apache_config.gsub("on","off")
    assert_not_equal(test_apache_config, edited_apache_config)

    #
    # Write the config file, and see if we've changed it.
    #
    File.open(@ssl.sites_available_file, "w+"){ |fh| fh.puts edited_apache_config; fh.puts checksum_line  }
    assert(@ssl.changed?)

    #
    # Now instead add the big warning to the file
    #
    File.open(@ssl.sites_available_file, "w+"){ |fh| fh.puts "# DO NOT EDIT THIS FILE - CHANGES WILL BE OVERWRITTEN"; fh.puts edited_apache_config }
    assert(!@ssl.changed?)
  end

end
