$:.unshift  "../lib/" if File.directory?("../lib")

require 'test/unit'
require 'tmpdir'
require 'symbiosis/ssl/selfsigned'

class SSLSelfSignedTest < Test::Unit::TestCase

  def setup
    Process.egid = 1000 if Process.gid == 0
    Process.euid = 1000 if Process.uid == 0

    @prefix = Dir.mktmpdir("srv")

    Process.euid = 0 if Process.uid == 0
    Process.egid = 0 if Process.gid == 0

    @prefix.freeze
    @domain = Symbiosis::Domain.new(nil, @prefix)
    @domain.create
    @client = Symbiosis::SSL::SelfSigned.new(@domain)
  end

  def teardown
    unless $DEBUG
      @domain.destroy  if @domain.is_a?( Symbiosis::Domain)
      FileUtils.rm_rf(@prefix) if @prefix and File.directory?(@prefix)
    end
  end

  ####
  #
  # Tests start here.
  #
  #####

  def test_request
    omit unless @client
    req = nil
    req = @client.request

    assert_kind_of(OpenSSL::X509::Request, req)
    assert_equal("/CN=#{@domain.name}", req.subject.to_s)

    #
    # Now test the altname stuff
    #
    ext_req = req.attributes.find{|a| a.oid == "extReq" }
    extensions = []
    ext_req.value.first.value.each do |ext|
      extensions << OpenSSL::X509::Extension.new(ext)
    end
    
    san_ext = extensions.find{|e| "subjectAltName" == e.oid}

    assert_kind_of(OpenSSL::X509::Extension, san_ext, "subjectAltName missing from CSR")

    san_domains      = san_ext.value.split(/[,\s]+/).map{|n| n.sub(/^DNS:(.+)$/,'\1')}
    expected_domains = ([@domain.name] + @domain.aliases).uniq

    assert((san_domains - expected_domains).empty?, "Extra domains were found in subjectAltName in the request: " + (san_domains - expected_domains).join(", ") )
    assert((expected_domains - san_domains).empty?, "Domains were missing from subjectAltName in the request: " + (expected_domains - san_domains).join(", ") )
  end  

  def test_key
    assert_kind_of(OpenSSL::PKey::PKey, @client.key)
    assert_kind_of(OpenSSL::PKey::RSA,  @client.rsa_key)
  end

  def test_certificate
    assert_kind_of(OpenSSL::X509::Certificate, @client.certificate)

    #
    # Make sure our new certificate is valid
    #
    assert(@domain.ssl_verify(@client.certificate, @client.key, nil, true))

  end

end
