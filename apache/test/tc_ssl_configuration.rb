
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


module Symbiosis 
  module Test
    class Http
      def directory
        File.join("/tmp", "srv", @name)
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
    @ssl.root_path = "/tmp"

    #
    # Copy some SSL certs over
    #
    FileUtils.mkdir_p(@domain.directory+"/config")
    
  end

  def teardown
    @domain.destroy unless $DEBUG
    FileUtils.rmdir "/tmp/srv"
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
    ip = "1.2.3.4"
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
    ip = "1.2.3.4"
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
    assert_nil(@ssl.certificate)

    #
    # Now write the file
    #
    File.open(@domain.directory+"/config/ssl.combined","w+"){|fh| fh.write crt.to_pem+key.to_pem}
    @ssl.certificate_file = @domain.directory+"/config/ssl.combined"

    #
    # Now it should read back the combined file correctly
    #
    assert_kind_of(crt.class, @ssl.certificate)
    assert_equal(crt.to_der, @ssl.certificate.to_der)

    #
    # Generate a new certificate
    #
    key, crt = do_generate_key_and_crt(@domain.name)
    #
    # Make sure it doesn't match the last one
    #
    assert_not_equal(crt.to_der, @ssl.certificate.to_der)

    File.open(@domain.directory+"/config/ssl.crt","w+"){|fh| fh.write crt.to_pem}
    @ssl.certificate_file = @domain.directory+"/config/ssl.crt"
    #
    # Now it should read back the individual file correctly
    #
    assert_equal(crt.to_der, @ssl.certificate.to_der)
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

  def test_certificate_chain
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
    # This should not verify yet
    #
    assert_nothing_raised{ @ssl.verify }

    #
    # TODO: test expired certificate
    #

    #
    # Now write a combined cert with a duff key.  This should not verify.
    #
    File.open(@domain.directory+"/config/ssl.combined","w+"){|fh| fh.write crt.to_pem+do_generate_key.to_pem}
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
    # This should verify now 
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

  def test_create_ssl_site
    
    
  end

  def test_outdated?

  end

end
