
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
    @key = do_generate_key
    @csr = do_generate_csr
    @crt = do_generate_cert
    
  end

  def teardown
    @domain.destroy unless $DEBUG
    FileUtils.rmdir "/tmp/srv"
  end

  #
  # Returns a private key
  #
  def do_generate_key
    OpenSSL::PKey::RSA.new(512)
  end

  def do_generate_csr(key = @key, domain = @domain.name)
    csr            = OpenSSL::X509::Request.new
    csr.version    = 0
    csr.subject    = OpenSSL::X509::Name.new( [ ["C","GB"], ["CN", domain]] )
    csr.public_key = key.public_key
    csr.sign( key, OpenSSL::Digest::SHA1.new )
    csr
  end

  def do_generate_cert(csr = @csr, key = @key, ca=nil)
    cert            = OpenSSL::X509::Certificate.new
    cert.subject    = csr.subject
    cert.issuer     = csr.subject
    cert.public_key = csr.public_key
    cert.not_before = Time.now
    cert.not_after  = Time.now + 60
    cert.serial     = 0x0
    cert.version    = 1 
    cert.sign( key, OpenSSL::Digest::SHA1.new )
    cert
  end
  
  
  def test_ssl_enabled?
  end

  def test_site_enabled?
  end

  def test_mandatory_ssl?
  end

  def test_remove_site
  end

  def test_ip
  end

  def test_certificate
  end

  def test_key
  end

  def test_certificate_chain_file
  end

  def test_certificate_chain
  end

  def test_avilable_certificate_files
    #
    # Write the certificate in various forms
    #
    File.open(@domain.directory+"/config/ssl.combined","w+"){|fh| fh.write @crt.to_pem+@key.to_pem}
    File.open(@domain.directory+"/config/ssl.key","w+"){|fh| fh.write @crt.to_pem+@key.to_pem}
    File.open(@domain.directory+"/config/ssl.crt","w+"){|fh| fh.write @crt.to_pem}
    File.open(@domain.directory+"/config/ssl.cert","w+"){|fh| fh.write @crt.to_pem}
    File.open(@domain.directory+"/config/ssl.pem","w+"){|fh| fh.write @crt.to_pem}
    
    #
    # Combined is preferred
    #
    assert_equal( %w(combined key crt cert pem).collect{|ext| @domain.directory+"/config/ssl."+ext}, 
                   @ssl.available_certificate_files)

    #
    # If a combined file contains a non-matching cert+key, don't return it
    #
    new_key = do_generate_key
    File.open(@domain.directory+"/config/ssl.combined","w+"){|fh| fh.write @crt.to_pem + new_key.to_pem}

    assert_equal( %w(key crt cert pem).collect{|ext| @domain.directory+"/config/ssl."+ext},
                  @ssl.available_certificate_files )
  end

  def test_available_keys
    #
    # Write the key to a number of files
    #
    File.open(@domain.directory+"/config/ssl.combined","w+"){|fh| fh.write @crt.to_pem+@key.to_pem}
    File.open(@domain.directory+"/config/ssl.key","w+"){|fh| fh.write @key.to_pem}
    File.open(@domain.directory+"/config/ssl.crt","w+"){|fh| fh.write @crt.to_pem}
    
    #
    # Combined is preferred
    #
    assert_equal( %w(combined key).collect{|ext| @domain.directory+"/config/ssl."+ext}, 
                  @ssl.available_key_files )

    #
    # If a combined file contains a non-matching cert+key, don't return it
    #
    new_key = do_generate_key
    File.open(@domain.directory+"/config/ssl.combined","w+"){|fh| fh.write @crt.to_pem + new_key.to_pem}
    assert_equal( [@domain.directory+"/config/ssl.key"], 
                  @ssl.available_key_files )
  end

  def test_find_matching_certificate_and_key
    #
    # Initially, the combined cert should contain both the certificate and the key
    #
    File.open(@domain.directory+"/config/ssl.combined","w+"){|fh| fh.write @crt.to_pem+@key.to_pem}
    File.open(@domain.directory+"/config/ssl.key","w+"){|fh| fh.write @crt.to_pem+@key.to_pem}
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
    File.open(@domain.directory+"/config/ssl.key","w+"){|fh| fh.write @key.to_pem}
    File.open(@domain.directory+"/config/ssl.crt","w+"){|fh| fh.write @crt.to_pem}
    assert_equal( [@domain.directory+"/config/ssl.crt", @domain.directory+"/config/ssl.key"], 
                  @ssl.find_matching_certificate_and_key )
    
    #
    # Now generate a new key.  Watch it fail
    #
    new_key = do_generate_key
    File.open(@domain.directory+"/config/ssl.combined","w+"){|fh| fh.write @crt.to_pem + new_key.to_pem}
    assert_equal( [@domain.directory+"/config/ssl.crt", @domain.directory+"/config/ssl.key"],
                  @ssl.find_matching_certificate_and_key )
  end

  def test_verify
    #
    # Write a combined cert
    #
    File.open(@domain.directory+"/config/ssl.combined","w+"){|fh| fh.write @crt.to_pem+@key.to_pem}


    #
    # Now make sure it verifies OK
    #
    assert_nothing_raised{ @ssl.certificate_file = @domain.directory+"/config/ssl.combined" }
    assert_nothing_raised{ @ssl.key_file         = @domain.directory+"/config/ssl.combined" }
    assert_nothing_raised{ @ssl.verify }

    #
    # TODO: test expired certificate
    #

    #
    # Now write a combined cert with a duff key.  This should not verify.
    #
    File.open(@domain.directory+"/config/ssl.combined","w+"){|fh| fh.write @crt.to_pem+do_generate_key.to_pem}
    assert_raise(OpenSSL::X509::CertificateError){ @ssl.verify }
   
    #
    # TODO: Work out how to do bundled verifications. Ugh.
    #
  end

  def test_create_ssl_site
  end

  def test_outdated?
  end

end
