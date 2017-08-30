$:.unshift  "../lib/" if File.directory?("../lib")

require 'test/unit'
require 'tmpdir'
require 'symbiosis'
require 'symbiosis/domain/ssl'
require 'symbiosis/ssl/selfsigned'
require 'mocha/test_unit'

class Symbiosis::SSL::Dummy < Symbiosis::SSL::CertificateSet
# def initialize(domain); end
end

class SSLTest < Test::Unit::TestCase

  @@serial=0

  def setup
    #
    # Check the root CA before starting.  This needs to write a symlink, so do
    # it before dropping privs.
    #
    do_check_root_ca

    #
    # Create our srv prefix as user 1000, if we're running as root.
    #
    Process.egid = 1000 if Process.gid == 0
    Process.euid = 1000 if Process.uid == 0
    @etc = Dir.mktmpdir('etc')

    @prefix = Dir.mktmpdir("srv")
    Symbiosis.etc = File.realpath @etc
    Symbiosis.prefix = File.realpath @prefix

    @etc.freeze
    @prefix.freeze
    @domain = Symbiosis::Domain.new(nil, @prefix)
    @domain.create

    @verbose = (($VERBOSE or $DEBUG) ? " --verbose " : "")

    testd = File.dirname(__FILE__)

    @script = File.expand_path(File.join(testd,"..","bin","symbiosis-ssl"))
    @script = '/usr/sbin/symbiosis-ssl' unless File.exist?(@script)
    @script += @verbose
  end

  def teardown
    #
    # Empty the SSL providers array.
    #
    while Symbiosis::SSL::PROVIDERS.pop ; end

    #
    # And repopulate it with any existing providers
    #
    ObjectSpace.each_object(Class).select { |k| k < Symbiosis::SSL::CertificateSet }.
      collect{|k| Symbiosis::SSL::PROVIDERS << k}

    unless $DEBUG
      @domain.destroy  if @domain.is_a?( Symbiosis::Domain)
      FileUtils.rm_rf(@prefix) if File.directory?(@prefix)
    end

    FileUtils.rm_rf(@etc) if File.directory?(@etc)

    Process.euid = 0 if Process.uid == 0
    Process.egid = 0 if Process.gid == 0
  end

  #####
  #
  # Helper methods
  #
  #####

  #
  # Checks to make sure our Root CA is set up.
  #
  def do_check_root_ca
    #
    # Our root CA.
    #
    root_ca_path = File.expand_path(File.join(File.dirname(__FILE__), "RootCA"))
    unless File.exist?(root_ca_path)
      warn "\n#{root_ca_path} missing"
      return nil
    end

    root_ca_cert_file = File.join(root_ca_path, "RootCA.crt")
    unless File.exist?(root_ca_cert_file)
      warn "\n#{root_ca_cert_file} missing"
      return nil
    end

    root_ca_key_file  = File.join(root_ca_path, "RootCA.key")
    unless File.exist?(root_ca_key_file)
      warn "\n#{root_ca_key_file} missing"
      return nil
    end

    root_ca_cert = OpenSSL::X509::Certificate.new(File.read(root_ca_cert_file))

    #
    # Make sure a symlink is in place so the root cert can be found.
    #
    root_ca_cert_symlink = File.join(root_ca_path, root_ca_cert.subject.hash.to_s(16)+ ".0")

    unless File.exist?(root_ca_cert_symlink)
      if File.writable?(root_ca_path)
        warn "\nCreating symlink to from #{root_ca_cert_file} to #{root_ca_cert_symlink}"
        File.symlink(File.basename(root_ca_cert_file),root_ca_cert_symlink)
        return root_ca_path
      else
        return nil
      end
    end

    return root_ca_path
  end

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
  def do_generate_crt(domain, options={})
    #
    # Generate a key if none has been specified
    #
    key = options[:key] ? options[:key] : do_generate_key
    ca_cert = options[:ca_cert]
    ca_key = options[:ca_key]
    subject_alt_name = options[:subject_alt_name]
    options[:not_before] ||= Time.now
    options[:not_after] ||= Time.now + 60

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
    crt.not_before = options[:not_before]
    crt.not_after  = options[:not_after]
    #
    # Make sure we increment the serial for each regeneration, to make sure
    # there are differences when regenerating a certificate for a new domain.
    #
    crt.serial     = @@serial
    @@serial += 1
    crt.version    = 2

    #
    # Add in our X509v3 extensions.
    #
    ef = OpenSSL::X509::ExtensionFactory.new
    ef.subject_certificate = crt
    if ca_cert.nil? or ca_key.nil?
      ef.issuer_certificate  = crt
    else
      ef.issuer_certificate  = ca_cert
    end

    #
    # Use the subjectAltName if one has been given.  This is for SNI, i.e. SSL
    # name-based virtual hosting (ish).
    #
    if subject_alt_name
      crt.add_extension(ef.create_extension("subjectAltName", "DNS:#{domain},DNS:#{subject_alt_name}"))
    else
      crt.add_extension(ef.create_extension("subjectAltName", "DNS:#{domain}"))
    end

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
  def do_generate_key_and_crt(domain, options={})
    options[:key] = do_generate_key
    return [options[:key], do_generate_crt(domain, options)]
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
    assert( !@domain.ssl_enabled? )

    #
    # Now set an IP.  This should still return false.
    #
    ip = "80.68.88.52"
    File.open(@domain.directory+"/config/ip","w+"){|fh| fh.puts ip}
    assert( !@domain.ssl_enabled? )

    #
    # Generate a key + cert.  It should now return true.
    #
    key, crt = do_generate_key_and_crt(@domain.name)
    File.open(@domain.directory+"/config/ssl.combined","w+"){|fh| fh.write crt.to_pem+key.to_pem}
    assert( @domain.ssl_enabled? )
  end

  def test_ssl_mandatory?
    #
    # First make sure this responds "false"
    #
    assert( !@domain.ssl_mandatory? )

    #
    # Now it should return true
    #
    FileUtils.touch(@domain.directory+"/config/ssl-only")
    assert( @domain.ssl_mandatory? )
  end

  def test_ssl_x509_certificate
    #
    # Generate a key
    #
    key, crt = do_generate_key_and_crt(@domain.name)

    #
    # Return nil if no certificate filename has been set
    #
    assert_nil(@domain.ssl_x509_certificate)

    #
    # Now write the file
    #
    File.open(@domain.directory+"/config/ssl.combined","w+"){|fh| fh.write crt.to_pem+key.to_pem}
    @domain.ssl_x509_certificate_file = @domain.directory+"/config/ssl.combined"

    #
    # Now it should read back the combined file correctly
    #
    assert_kind_of(crt.class, @domain.ssl_x509_certificate)
    assert_equal(crt.to_der, @domain.ssl_x509_certificate.to_der)

    #
    # Generate a new certificate
    #
    key, crt = do_generate_key_and_crt(@domain.name)
    #
    # Make sure it doesn't match the last one
    #
    assert_not_equal(crt.to_der, @domain.ssl_x509_certificate.to_der)

    File.open(@domain.directory+"/config/ssl.crt","w+"){|fh| fh.write crt.to_pem}
    @domain.ssl_x509_certificate_file = @domain.directory+"/config/ssl.crt"
    #
    # Now it should read back the individual file correctly
    #
    assert_equal(crt.to_der, @domain.ssl_x509_certificate.to_der)
  end

  #
  # Sh
  #
  def test_ssl_key
    #
    # Generate a key and cert
    #
    key, crt = do_generate_key_and_crt(@domain.name)

    #
    # Return nil if no certificate filename has been set
    #
    assert_nil(@domain.ssl_key)

    File.open(@domain.directory+"/config/ssl.combined","w+"){|fh| fh.write crt.to_pem+key.to_pem}
    @domain.ssl_key_file = @domain.directory+"/config/ssl.combined"

    #
    # Now it should read back the combined file correctly
    #
    assert_kind_of(key.class, @domain.ssl_key)
    assert_equal(key.to_der, @domain.ssl_key.to_der)

    #
    # Generate a new key
    #
    key = do_generate_key

    #
    # Make sure it doesn't match the last one
    #
    assert_not_equal(key.to_der, @domain.ssl_key.to_der)

    File.open(@domain.directory+"/config/ssl.key","w+"){|fh| fh.write key.to_pem}
    @domain.ssl_key_file = @domain.directory+"/config/ssl.key"

    assert_equal(key.to_der, @domain.ssl_key.to_der)
  end

  def test_ssl_available_certificate_files
    #
    # Generate a key and cert
    #
    key, crt = do_generate_key_and_crt(@domain.name)
    oldcrt = do_generate_crt(@domain.name, {
      :key => key,
      :not_before => Time.now - 200,
      :not_after => Time.now + 10 })

    #
    # Write the certificate in various forms
    #
    File.open(@domain.directory+"/config/ssl.combined","w+"){|fh| fh.write oldcrt.to_pem+key.to_pem}
    File.open(@domain.directory+"/config/ssl.key","w+"){|fh| fh.write crt.to_pem+key.to_pem}
    File.open(@domain.directory+"/config/ssl.crt","w+"){|fh| fh.write oldcrt.to_pem}
    File.open(@domain.directory+"/config/ssl.cert","w+"){|fh| fh.write oldcrt.to_pem}
    File.open(@domain.directory+"/config/ssl.pem","w+"){|fh| fh.write oldcrt.to_pem}

    #
    # Newest is preferred
    #
    assert_equal(  @domain.directory+"/config/ssl.key",
                   @domain.ssl_available_certificate_files.first)

    #
    # If a combined file contains a non-matching cert+key, don't return it
    #
    new_key = do_generate_key
    File.open(@domain.directory+"/config/ssl.combined","w+"){|fh| fh.write crt.to_pem + new_key.to_pem}

    assert(!@domain.ssl_available_certificate_files.include?(@domain.directory+"/config/ssl.combined"))
  end

  def test_ssl_available_key_files
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
                  @domain.ssl_available_key_files )

    #
    # If a combined file contains a non-matching cert+key, don't return it
    #
    new_key = do_generate_key
    assert(!crt.check_private_key(new_key))

    File.open(@domain.directory+"/config/ssl.combined","w+"){|fh| fh.write crt.to_pem + new_key.to_pem}

    assert_equal( [@domain.directory+"/config/ssl.key"],
                  @domain.ssl_available_key_files )
  end

  def test_ssl_find_matching_certificate_and_key
    #
    # Generate a key and cert
    #
    key, crt = do_generate_key_and_crt(@domain.name)

    #
    # If no key and cert are found, nil is returned.
    #
    assert_nil( @domain.ssl_find_matching_certificate_and_key )

    #
    # Initially, the combined cert should contain both the certificate and the key
    #
    File.open(@domain.directory+"/config/ssl.combined","w+"){|fh| fh.write crt.to_pem+key.to_pem}
    File.open(@domain.directory+"/config/ssl.key","w+"){|fh| fh.write crt.to_pem+key.to_pem}
    assert_equal( [@domain.directory+"/config/ssl.combined"]*2,
                  @domain.ssl_find_matching_certificate_and_key )

    #
    # Now delete that file, and see what comes out.  We expect the key to be first now.
    #
    FileUtils.rm_f(@domain.directory+"/config/ssl.combined")
    assert_equal( [@domain.directory+"/config/ssl.key"]*2,
                  @domain.ssl_find_matching_certificate_and_key )

    #
    # Now recreate a key which is only a key, and see if we get the correct cert returned.
    #
    File.open(@domain.directory+"/config/ssl.key","w+"){|fh| fh.write key.to_pem}
    File.open(@domain.directory+"/config/ssl.crt","w+"){|fh| fh.write crt.to_pem}
    assert_equal( [@domain.directory+"/config/ssl.crt", @domain.directory+"/config/ssl.key"],
                  @domain.ssl_find_matching_certificate_and_key )

    #
    # Now generate a new key, and corrupt the combined certificate.
    # find_matching_certificate_and_key should now return the separate,
    # matching key and cert.
    #
    new_key = do_generate_key
    File.open(@domain.directory+"/config/ssl.combined","w+"){|fh| fh.write crt.to_pem + new_key.to_pem}
    assert_equal( [@domain.directory+"/config/ssl.crt", @domain.directory+"/config/ssl.key"],
                  @domain.ssl_find_matching_certificate_and_key )

    #
    # Now remove the crt file, leaving the duff combined cert, and the other
    # key.  This should return nil, since the combined file contains the
    # certificate that matches the *separate* key, and a non-matching key,
    # rendering it useless.
    #
    FileUtils.rm_f(@domain.directory+"/config/ssl.crt")
    assert_nil(@domain.ssl_find_matching_certificate_and_key)

  end


  #################################
  #
  # The following methods are not explicitly tested:
  #    ssl_certificate_chain_file
  #    ssl_add_ca_path(path)
  #    ssl_certificate_store
  #
  # since they're all done as part of the verification tests below.
  #

  def test_ssl_verify_self_signed
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
    assert_nothing_raised{ @domain.ssl_x509_certificate_file = @domain.directory+"/config/ssl.combined" }
    assert_nothing_raised{ @domain.ssl_key_file         = @domain.directory+"/config/ssl.combined" }

    #
    # This should verify.
    #
    assert_nothing_raised{ @domain.ssl_verify(@domain.ssl_x509_certificate, @domain.ssl_key, @domain.ssl_certificate_store, true) }

    #
    # Generate another key
    #
    new_key = do_generate_key

    #
    # Now write a combined cert with this new key.  This should not verify.
    #
    File.open(@domain.directory+"/config/ssl.combined","w+"){|fh| fh.write crt.to_pem+new_key.to_pem}
    assert_raise(OpenSSL::X509::CertificateError){ @domain.ssl_verify(@domain.ssl_x509_certificate, @domain.ssl_key, @domain.ssl_certificate_store, true) }

    #
    # Now sign the certificate with this new key.  This should cause the verification to fail.
    #
    crt.sign( new_key, OpenSSL::Digest::SHA1.new )
    File.open(@domain.directory+"/config/ssl.combined","w+"){|fh| fh.write crt.to_pem+key.to_pem}
    assert_raise(OpenSSL::X509::CertificateError){ @domain.ssl_verify(@domain.ssl_x509_certificate, @domain.ssl_key, @domain.ssl_certificate_store, true) }

    #
    # Now write a combined cert with the new key.  This should still not
    # verify, as the public key on the certificate will not match the private
    # key, even though we've signed the cert with this new private key.
    #
    File.open(@domain.directory+"/config/ssl.combined","w+"){|fh| fh.write crt.to_pem+new_key.to_pem}
    assert_raise(OpenSSL::X509::CertificateError){ @domain.ssl_verify(@domain.ssl_x509_certificate, @domain.ssl_key, @domain.ssl_certificate_store, true) }
  end

  def test_ssl_verify_with_root_ca
    #
    # Add the Root CA path
    #
    root_ca_path = do_check_root_ca
    if root_ca_path.nil?
      warn "\nRootCA could not be found"
      return
    end
    @domain.ssl_add_ca_path(root_ca_path)

    #
    # Get our Root cert and key
    #
    ca_cert = OpenSSL::X509::Certificate.new(File.read("#{root_ca_path}/RootCA.crt"))
    ca_key  = OpenSSL::PKey::RSA.new(File.read("#{root_ca_path}/RootCA.key"))

    #
    # Generate a key and cert
    #
    key = do_generate_key
    crt = do_generate_crt(@domain.name, {
      :key     => key,
      :ca_cert => ca_cert,
      :ca_key  => ca_key })

    #
    # Write a combined cert
    #
    File.open(@domain.directory+"/config/ssl.combined","w+"){|fh| fh.write crt.to_pem+key.to_pem}

    #
    # This should verify just fine.
    #
    assert_nothing_raised{ @domain.ssl_x509_certificate_file = @domain.directory+"/config/ssl.combined" }
    assert_nothing_raised{ @domain.ssl_key_file         = @domain.directory+"/config/ssl.combined" }
    assert_nothing_raised{ @domain.ssl_verify(@domain.ssl_x509_certificate, @domain.ssl_key, @domain.ssl_certificate_store, true) }
  end

  def test_ssl_verify_with_intermediate_ca
    #
    # Use our intermediate CA.
    #
    int_ca_path = File.expand_path(File.join(File.dirname(__FILE__), "IntermediateCA"))
    ca_cert = OpenSSL::X509::Certificate.new(File.read("#{int_ca_path}/IntermediateCA.crt"))
    ca_key  = OpenSSL::PKey::RSA.new(File.read("#{int_ca_path}/IntermediateCA.key"))

    #
    # Add the Root CA path
    #
    do_check_root_ca
    root_ca_path = File.expand_path(File.join(File.dirname(__FILE__), "RootCA"))
    @domain.ssl_add_ca_path(root_ca_path)

    #
    # Generate a key and cert
    #
    key = do_generate_key
    crt = do_generate_crt(@domain.name, {
      :key     => key,
      :ca_cert => ca_cert,
      :ca_key  => ca_key })

    #
    # Write a combined cert
    #
    File.open(@domain.directory+"/config/ssl.combined","w+"){|fh| fh.write crt.to_pem+key.to_pem}

    #
    # This should not verify yet, as the bundle hasn't been copied in place.
    #
    assert_nothing_raised{ @domain.ssl_x509_certificate_file = @domain.directory+"/config/ssl.combined" }
    assert_nothing_raised{ @domain.ssl_key_file         = @domain.directory+"/config/ssl.combined" }
    assert_raise(OpenSSL::X509::CertificateError){ @domain.ssl_verify(@domain.ssl_x509_certificate, @domain.ssl_key, @domain.ssl_certificate_store, true) }

    #
    # Now copy the bundle in place
    #
    FileUtils.cp("#{int_ca_path}/IntermediateCA.crt",@domain.directory+"/config/ssl.bundle")

    #
    # Now it should verify just fine.
    #
    assert_nothing_raised{ @domain.ssl_verify(@domain.ssl_x509_certificate, @domain.ssl_key, @domain.ssl_certificate_store, true) }
  end

  def test_ssl_verify_with_sni
    other_domain = Symbiosis::Domain.new(nil, @prefix)
    other_domain.create

    third_domain = Symbiosis::Domain.new(nil, @prefix)
    third_domain.create

    key = do_generate_key
    crt = do_generate_crt(@domain.name, {
      :key => key,
      :subject_alt_name => other_domain.name })

    #
    # This should verify.
    #
    assert_nothing_raised{ @domain.ssl_verify(crt, key, nil, true) }

    #
    # This should also verify.
    #
    assert_nothing_raised{ other_domain.ssl_verify(crt, key, nil, true) }

    #
    # This should not verify.
    #
    assert_raise(OpenSSL::X509::CertificateError){ third_domain.ssl_verify(crt, key, nil, true) }
  end


  def test_ssl_verify_with_wildcard
    other_domain = Symbiosis::Domain.new("other."+@domain.name, @prefix)
    other_domain.create

    third_domain = Symbiosis::Domain.new(nil, @prefix)
    third_domain.create


    key = do_generate_key
    crt = do_generate_crt("*."+@domain.name, {:key => key})

    #
    # This should verify.
    #
    assert_nothing_raised{ @domain.ssl_verify(crt, key, nil, true) }

    #
    # This should also verify.
    #
    assert_nothing_raised{ other_domain.ssl_verify(crt, key, nil, true) }

    #
    # This should not verify.
    #
    assert_raise(OpenSSL::X509::CertificateError){ third_domain.ssl_verify(crt, key, nil, true) }
  end

  def test_ssl_provider
    while Symbiosis::SSL::PROVIDERS.pop ; end

    assert_equal(false, @domain.ssl_provider, "#ssl_provider should return false if no providers available")

    #
    # Add our provider in
    #
    Symbiosis::SSL::PROVIDERS << Symbiosis::SSL::Dummy
    assert_equal("dummy", @domain.ssl_provider, "#ssl_provider should return the first available provider")

    [[ "dummy", "dummy" ],
      [  "../../../evil", "evil" ],
      [  "false", false ]].each do |contents, result|

      File.open(@domain.directory+"/config/ssl-provider","w+"){|fh| fh.puts(contents)}
      assert_equal(result, @domain.ssl_provider)
    end

  end

  def test_ssl_provider_class
    while Symbiosis::SSL::PROVIDERS.pop ; end

    assert_equal(nil, @domain.ssl_provider_class, "#ssl_provider_class should return nil if no providers available")

    #
    # Add our provider in
    #
    Symbiosis::SSL::PROVIDERS << Symbiosis::SSL::Dummy
    assert_equal(Symbiosis::SSL::Dummy, @domain.ssl_provider_class, "#ssl_provider_class should return the first available provider")


    [[ "dummy", Symbiosis::SSL::Dummy ],
      [  "../../../evil", nil ],
      [  "false", nil ]].each do |contents, result|

      File.open(@domain.directory+"/config/ssl-provider","w+"){|fh| fh.puts(contents)}
      assert_equal(result, @domain.ssl_provider_class)
    end
  end

  def test_ssl_fetch_new_certificate
    while Symbiosis::SSL::PROVIDERS.pop ; end

    assert_equal(nil, @domain.ssl_fetch_new_certificate, "#ssl_fetch_new_certificate should return nil if no providers available")

    Symbiosis::SSL::PROVIDERS << Symbiosis::SSL::Dummy
    assert_equal(nil, @domain.ssl_fetch_new_certificate, "#ssl_fetch_new_certificate should return nil if the provider does not look compatible")

    #
    # Use our intermediate CA, and generate and sign the certificate
    #
    int_ca_path = File.expand_path(File.join(File.dirname(__FILE__), "IntermediateCA"))
    ca_cert = OpenSSL::X509::Certificate.new(File.read("#{int_ca_path}/IntermediateCA.crt"))
    ca_key  = OpenSSL::PKey::RSA.new(File.read("#{int_ca_path}/IntermediateCA.key"))
    request = OpenSSL::X509::Request.new
    key, cert = do_generate_key_and_crt(@domain.name, {:ca_key => ca_key, :ca_cert => ca_cert})

    #
    # Set up our dummy provider
    #
    Symbiosis::SSL::Dummy.any_instance.stubs(:verify_and_request_certificate!).returns(request)
    Symbiosis::SSL::Dummy.any_instance.stubs(:register).returns(true)
    Symbiosis::SSL::Dummy.any_instance.stubs(:registered?).returns(false)
    Symbiosis::SSL::Dummy.any_instance.stubs(:key).returns(key)
    Symbiosis::SSL::Dummy.any_instance.stubs(:certificate).returns(cert)
    Symbiosis::SSL::Dummy.any_instance.stubs(:bundle).returns([ca_cert])
    Symbiosis::SSL::Dummy.any_instance.stubs(:request).returns(request)

    set = @domain.ssl_fetch_new_certificate

    assert_equal(set.bundle, [ca_cert])
    assert_equal(set.key, key)
    assert_equal(set.certificate, cert)
    assert_equal(set.request, request)

    assert_equal("0", @domain.ssl_next_set_name)
    set.name = "0"

    #
    # Now write our set out.
    #
    dir = set.write
    expected_dir = File.join(@prefix, @domain.name, "config", "ssl", "sets", "0")
    assert_equal(expected_dir, dir)

    #
    # make sure everything verifies OK, both as key, crt, bundle, and combined.
    #
    [ %w(key crt bundle), %w(combined)*3 ].each do |exts|
      key = OpenSSL::PKey::RSA.new(File.read(File.join(dir, "ssl.#{exts[0]}")))
      cert = OpenSSL::X509::Certificate.new(File.read(File.join(dir, "ssl.#{exts[1]}")))
      store = OpenSSL::X509::Store.new
      store.add_file(File.join(dir, "ssl.#{exts[2]}"))
      assert(@domain.ssl_verify(cert, key, store))
    end

  end

  def test_ssl_current_set
    current = File.join(@domain.config_dir, "ssl", "c")
    Symbiosis::Utils.mkdir_p(current)

    #
    # We need to write out a key+cert for the set to be valid
    #
    key, crt = do_generate_key_and_crt(@domain.name)
    Symbiosis::Utils.set_param("ssl.key", key, current)
    Symbiosis::Utils.set_param("ssl.crt", crt, current)

    FileUtils.ln_sf(current, File.join(@domain.config_dir, "ssl", "b"))
    FileUtils.ln_sf("b", File.join(@domain.config_dir, "ssl", "current"))

    assert_equal("b", File.readlink(File.join(@domain.config_dir, "ssl", "current")))
    assert_equal(current, File.readlink(File.join(@domain.config_dir, "ssl", "b")))

    assert_equal("c",@domain.ssl_current_set.name)
  end

  def test_ssl_latest_set_and_rollover
    #
    # Set up our stuff
    #
    now = Time.now
    ssl_dir  = File.join(@domain.config_dir, "ssl")
    sets_dir = File.join(ssl_dir, "sets")

    not_before = now - 86400*2
    not_after  = now - 1

    int_ca_path = File.expand_path(File.join(File.dirname(__FILE__), "IntermediateCA"))
    ca_cert = OpenSSL::X509::Certificate.new(File.read("#{int_ca_path}/IntermediateCA.crt"))
    ca_key  = OpenSSL::PKey::RSA.new(File.read("#{int_ca_path}/IntermediateCA.key"))

    root_ca_path = File.expand_path(File.join(File.dirname(__FILE__), "RootCA"))
    root_ca_cert = OpenSSL::X509::Certificate.new(File.read("#{root_ca_path}/RootCA.crt"))

    bundle = ca_cert.to_pem + root_ca_cert.to_pem

    4.times do |i|
      key, crt = do_generate_key_and_crt(@domain.name, {:ca_key => ca_key, :ca_cert => ca_cert, :not_before => not_before, :not_after => not_after})

      set_dir = File.join(sets_dir, i.to_s)
      Symbiosis::Utils.mkdir_p(set_dir)
      Symbiosis::Utils.set_param("ssl.key", key, set_dir)
      Symbiosis::Utils.set_param("ssl.crt", crt, set_dir)
      Symbiosis::Utils.set_param("ssl.bundle", bundle, set_dir)

      not_before += 86400
      not_after  += 86400
    end

    current_path = File.join(ssl_dir, "current")

    FileUtils.ln_sf(File.expand_path("sets/2", ssl_dir), current_path)

    available_sets = @domain.ssl_available_sets

    assert(!available_sets.map(&:name).include?("current"), "The avaialble sets should not include the 'current' symlink")
    missing_sets = (%w(1 2) - available_sets.map(&:name))
    assert(missing_sets.empty?, "Some sets were missing: #{missing_sets.join(", ")}")

    extra_sets = (available_sets.map(&:name) - %w(1 2))
    assert(extra_sets.empty?, "Extra sets were returned: #{extra_sets.join(", ")}")

    #
    # Now we're going to test rollover.  At the moment we're pointing at the
    # most recent set, so we should get false back, as nothing has changed.
    #
    assert_equal(false, @domain.ssl_rollover)
    assert_equal(File.expand_path("2", sets_dir), File.expand_path(File.readlink(current_path), ssl_dir))

    #
    # Now change the link, and it should get set back to "2"
    #
    File.unlink(current_path)
    assert_equal(true, @domain.ssl_rollover)
    assert_equal(File.expand_path("2", sets_dir), File.expand_path(File.readlink(current_path), ssl_dir))

    File.unlink(current_path)
    File.symlink("sets/1", current_path)
    assert_equal(File.expand_path("1", sets_dir), File.expand_path(File.readlink(current_path), ssl_dir))
    assert_equal(true, @domain.ssl_rollover)
    assert_equal(File.expand_path("2", sets_dir), File.expand_path(File.readlink(current_path), ssl_dir))

    #
    # OK now remove the current set, and see if we cope with broken symlinks
    #
    FileUtils.remove_entry_secure(File.join(sets_dir, "2"))
    assert_equal(true, @domain.ssl_rollover)
    assert_equal(File.expand_path("1", sets_dir), File.expand_path(File.readlink(current_path), ssl_dir))
  end

  def test_ssl_magic
    #
    # This requires the Self-signed provider to be in place
    #

    @domain.ssl_provider = "selfsigned"

    ssl_dir  = File.join(@domain.config_dir, "ssl")
    sets_dir = File.join(ssl_dir, "sets")

    Symbiosis::Utils.mkdir_p(sets_dir)
    #
    # Test with the no_generate flag
    #
    result = nil
    assert_nothing_raised{ result = @domain.ssl_magic(14, false) }
    assert(!result)

    assert(Dir.glob( File.join(sets_dir, '*') ).empty?, "There should be no sets generated if do_generate is false" )

    #
    # Test with the no_rollover flag.  This should generate a set, but not link it to current.
    #

    expected_dir = File.join(sets_dir, @domain.ssl_next_set_name)
    current_dir  = File.join(ssl_dir, "current")

    assert_nothing_raised{ result = @domain.ssl_magic(14, true, false) }
    assert(File.directory?(expected_dir), "A set should have been generated in #{expected_dir}")
    assert(!File.exist?(current_dir), "The link to current should not have been generated yet")

    #
    # Now run it normally. This should create the symlink
    #
    assert_nothing_raised{ result = @domain.ssl_magic(14) }
    assert(File.exist?(current_dir), "The link to current should have been generated.")
    assert_equal(expected_dir, File.readlink(current_dir))

    #
    # And run it again.  Nothing should change
    #
    assert_nothing_raised{ result = @domain.ssl_magic(14) }
    assert_equal(expected_dir, File.readlink(current_dir))

    #
    # Now test rolling over lots of times
    #
    10.times do |s|
      expected_dir = File.join(sets_dir, @domain.ssl_next_set_name)
      assert_nothing_raised{ result = @domain.ssl_magic(500) }
      assert(File.directory?(expected_dir), "Failed to generate set #{expected_dir} correctly")
      assert_equal(expected_dir, File.readlink(current_dir))
    end

    #
    # Now create a directory in the way
    #
    expected_dir = File.join(sets_dir, @domain.ssl_next_set_name)
    Symbiosis::Utils.mkdir_p(expected_dir)
    assert_nothing_raised{ result = @domain.ssl_magic(500) }

    #
    # Now create a file in the way
    #
    expected_dir = File.join(sets_dir, @domain.ssl_next_set_name)
    FileUtils.touch(expected_dir)
    assert_nothing_raised{ result = @domain.ssl_magic(500) }

    #
    # Now test a forced roll-over. First make sure nothing happens with force
    # set to false.
    #
    current_cert = @domain.ssl_certificate
    @domain.ssl_magic(14)
    assert_equal(current_cert.to_pem, @domain.ssl_certificate.to_pem, "Existing certificate replaced, even with force off")

    #
    # And do it again, this time set the flag to true.  It should regenerate it.
    #
    @domain.ssl_magic(15,true,true)
    assert(current_cert.to_pem != @domain.ssl_certificate.to_pem, "Certificate not replaced with force on")


  end

  def test_ssl_hooks
    #
    # This requires the Self-signed provider to be in place
    #

    ssl_domain = @domain
    ssl_domain.ssl_provider = 'selfsigned'

    ssl_dir  = File.join(ssl_domain.config_dir, 'ssl')
    sets_dir = File.join(ssl_dir, 'sets')

    Symbiosis::Utils.mkdir_p(sets_dir)

    regular_domain = Symbiosis::Domain.new(nil, @prefix)
    regular_domain.create

    args_path = Symbiosis.path_in_etc('hook.args')
    out_path = Symbiosis.path_in_etc('hook.output')

    hook = <<HOOK
#!/bin/bash

echo "$1" > #{args_path}
cat > #{out_path}
HOOK

    FileUtils.mkdir_p Symbiosis.path_in_etc('symbiosis/ssl-hooks.d')

    IO.write Symbiosis.path_in_etc('symbiosis/ssl-hooks.d/hook'), hook, mode: 'w', perm: 0755

    system("#{@script} --etc-dir=#{@etc} --prefix=#{@prefix}")
    
    args = IO.read args_path
    out = IO.read out_path

    assert_equal "live-update\n", args
    assert_equal "#{ssl_domain.name}\n", out
  end
end
