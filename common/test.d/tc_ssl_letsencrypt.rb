$:.unshift  "../lib/" if File.directory?("../lib")

require 'test/unit'
require 'tmpdir'

if RUBY_VERSION =~ /^[2-9]\./
  require 'symbiosis/ssl/letsencrypt'
end

require 'webmock/test_unit'
WebMock.allow_net_connect!

class SSLLetsEncryptTest < Test::Unit::TestCase

  def setup
    omit "acme-client requires ruby > 2.0"  unless defined? Symbiosis::SSL::LetsEncrypt
    WebMock.disable_net_connect!

    @prefix = Dir.mktmpdir("srv")
    @prefix.freeze
    @domain = Symbiosis::Domain.new(nil, @prefix)
    @domain.create
    
    @endpoint = "https://imaginary.test.endpoint:443" 
    @http01_challenge =  {} # This is where we store our challenges
    @authz_template = Addressable::Template.new "#{@endpoint}/acme/authz/{sekrit}/0"

    #
    # Stub requests to our imaginary endpoint
    #
    stub_request(:head, /.*/).to_return{|r| do_head(r)}
    stub_request(:post, "#{@endpoint}/acme/new-reg").to_return{|r| do_post_new_reg(r)}
    stub_request(:post, "#{@endpoint}/acme/new-authz").to_return{|r| do_post_new_authz(r)}
    stub_request(:post, @authz_template).to_return{|r| do_post_authz(r)}
    stub_request(:get,  @authz_template).to_return{|r| do_get_authz(r)}
    stub_request(:post, "#{@endpoint}/acme/new-cert").to_return{|r| do_post_new_cert(r)}
    stub_request(:get,  "#{@endpoint}/bundle").to_return{|r| do_get_bundle(r)} 


    @client = Symbiosis::SSL::LetsEncrypt.new(@domain)
    @client.config()[:endpoint] = @endpoint
  end

  def teardown
    WebMock.allow_net_connect!
    unless $DEBUG
      @domain.destroy  if @domain.is_a?( Symbiosis::Domain)
      FileUtils.rm_rf(@prefix) if @prefix and File.directory?(@prefix)
    end
  end

  #####
  #
  # Helper methods
  #
  #####
  
  def setup_root_ca
    #
    # Our root CA.
    #
    root_ca_path = File.expand_path(File.join(File.dirname(__FILE__), "RootCA"))
    root_ca_crt_file = File.join(root_ca_path, "RootCA.crt")
    root_ca_key_file  = File.join(root_ca_path, "RootCA.key")
    @root_ca_crt = OpenSSL::X509::Certificate.new(File.read(root_ca_crt_file))
    @root_ca_key  = OpenSSL::PKey::RSA.new(File.read(root_ca_key_file))
  end

  def do_head(request)
    {:status => 405, :headers => {"Replay-Nonce" => Symbiosis::Utils.random_string(20)}}
  end

  def do_post_new_reg(request)
    {:status => 201, 
      :headers => {
        "Location" => "#{@endpoint}/acme/reg/asdf", 
        "Link" => "<#{@endpoint}/acme/new-authz>;rel=\"next\",<#{@endpoint}/acme/terms>;rel=\"terms-of-service\""
      }
    }
  end

  def do_post_new_authz(request)
    req     = JSON.load(request.body)
    payload = JSON.load(UrlSafeBase64.decode64(req["payload"]))
    sekrit  = Symbiosis::Utils.random_string(20).downcase

    @http01_challenge[sekrit] = {
      "type" => "http-01",
      "uri" => "#{@endpoint}/acme/authz/#{sekrit}/0",
      "token" => Symbiosis::Utils.random_string(20) 
    }

    response_payload = {
      "status" => "pending",
      "identifier" => payload["identifier"],
      "challenges" => [ @http01_challenge[sekrit] ],
      "combinations" => [[0]]
    }

    {:status => 201, :body => JSON.dump(response_payload), :headers => {"Content-Type" => "application/json", "Location" => "#{@endpoint}/acme/authz/#{sekrit}", "Link" => "<#{@endpoint}/acme/new-authz>;rel=\"next\""}}
  end

  def do_post_authz(request)
    req     = JSON.load(request.body)
    payload = JSON.load(UrlSafeBase64.decode64(req["payload"]))
    sekrit  = @authz_template.extract(request.uri)["sekrit"]

    @http01_challenge[sekrit].merge!({
      "keyAuthorization" => payload["keyAuthorization"],
      "status" => "pending" })

    {:status => 200, :body => JSON.dump(@http01_challenge[sekrit]),  :headers => {"Content-Type" => "application/json"}}
  end

  def do_get_authz(request)
    sekrit = @authz_template.extract(request.uri)["sekrit"]

    @http01_challenge[sekrit].merge!({
      "status" => "valid",
      "validated" => Time.now,
      "expires" =>  (Date.today + 90) })

    {:status => 200, :body => JSON.dump(@http01_challenge[sekrit]),  :headers => {"Content-Type" => "application/json"}}
  end

  def do_post_new_cert(request)
    req = JSON.load(request.body)
    payload = JSON.load(UrlSafeBase64.decode64(req["payload"]))
    csr = OpenSSL::X509::Request.new(UrlSafeBase64.decode64(payload["csr"]))

    setup_root_ca

    crt            = OpenSSL::X509::Certificate.new
    crt.subject    = csr.subject
    crt.issuer     = @root_ca_crt.subject
    crt.public_key = csr.public_key
    crt.not_before = Time.now
    crt.not_after  = Time.now + 90*86400
    crt.serial     = Time.now.to_i
    crt.version    = 2


    #
    # Add in our X509v3 extensions.
    #
    ef = OpenSSL::X509::ExtensionFactory.new
    ef.subject_certificate = crt
    ef.issuer_certificate  = @root_ca_crt

    crt.extensions = [
      ef.create_extension("basicConstraints","CA:FALSE", true),
      ef.create_extension("subjectKeyIdentifier", "hash"),
      ef.create_extension("authorityKeyIdentifier", "keyid:always,issuer:always")
    ]

    #
    # Add all the other extension requests.
    #
    ext_req = csr.attributes.find{|a| a.oid == "extReq" }
    ext_req.value.first.value.each do |ext|
      crt.add_extension(OpenSSL::X509::Extension.new(ext))
    end

    crt.sign(@root_ca_key, OpenSSL::Digest::SHA256.new)

    {:status => 200, :body => crt.to_s, :headers => {"link" => "<#{@endpoint}/bundle>;rel=\"up\""}}
  end

  def do_get_bundle(r)
    setup_root_ca
    {:status => 200, :body => @root_ca_crt}
  end

  ####
  #
  # Tests start here.
  #
  #####

  def test_register
    omit unless @client
    result = nil
    result = @client.register

    assert(result, "#register should return true")
  end

  def test_verify
    omit unless @client
    result = nil
    result = @client.verify

    assert(result, "#verify should return true")
  end

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
    omit unless @client
    assert_kind_of(OpenSSL::PKey::PKey, @client.key)
    assert_kind_of(OpenSSL::PKey::RSA,  @client.rsa_key)
  end

  def test_acme_certificate
    omit unless @client
    assert_kind_of(Acme::Certificate, @client.acme_certificate)
  end

  def test_domain_ssl_from_letsencrypt
   #    @domain.ssl_from_letsencrypt(@endpoint)
  end

end
