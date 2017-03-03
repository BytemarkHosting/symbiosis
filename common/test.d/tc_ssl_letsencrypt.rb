$:.unshift  "../lib/" if File.directory?("../lib")

require 'test/unit'
require 'tmpdir'
require 'symbiosis/domain/ssl'

if RUBY_VERSION =~ /^[2-9]\./
  require 'symbiosis/ssl/letsencrypt'
end

require 'webmock/test_unit'
WebMock.allow_net_connect!

class SSLLetsEncryptTest < Test::Unit::TestCase

  def setup
    omit "acme-client requires ruby > 2.0"  unless defined? Symbiosis::SSL::LetsEncrypt
    WebMock.disable_net_connect!

    Process.egid = 1000 if Process.gid == 0
    Process.euid = 1000 if Process.uid == 0

    @prefix = Dir.mktmpdir("srv")

    Process.euid = 0 if Process.uid == 0
    Process.egid = 0 if Process.gid == 0

    @prefix.freeze
    @domain = Symbiosis::Domain.new(nil, @prefix)
    @domain.create
    @state = "pending"

    @registered_keys = []

    @endpoint = "https://imaginary.test.endpoint:443"
    @http01_challenge =  {} # This is where we store our challenges
    @authz_template = Addressable::Template.new "#{@endpoint}/acme/authz/{sekrit}/0"
    @authz_challenges_template = Addressable::Template.new "#{@endpoint}/acme/authz/{sekrit}"


    #
    # Stub requests to our imaginary endpoint
    #
    stub_request(:head, /.*/).to_return{|r| do_head(r)}
    stub_request(:post, "#{@endpoint}/acme/new-reg").to_return{|r| do_post_new_reg(r)}
    stub_request(:post, "#{@endpoint}/acme/new-authz").to_return{|r| do_post_new_authz(r)}
    stub_request(:post, @authz_template).to_return{|r| do_post_authz(r)}
    stub_request(:get,  @authz_template).to_return{|r| do_get_authz(r)}
    stub_request(:get,  @authz_challenges_template).to_return{|r| do_get_authz_challenges(r)}
    stub_request(:post, "#{@endpoint}/acme/new-cert").to_return{|r| do_post_new_cert(r)}
    stub_request(:get,  "#{@endpoint}/bundle").to_return{|r| do_get_bundle(r)}

    @client = Symbiosis::SSL::LetsEncrypt.new(@domain)
    @client.config()[:endpoint] = @endpoint

    Symbiosis::Utils.set_param("endpoint", @endpoint, File.join(@domain.config_dir, "ssl", "letsencrypt"))
  end

  def teardown
    WebMock.allow_net_connect!
    WebMock.reset!
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

  def do_check_key(request)
    protect = JSON.load(Base64.urlsafe_decode64(request["protected"]))
    key = nil
    if protect.is_a?(Hash) and
      protect.has_key?("jwk") and
      protect["jwk"].is_a?(Hash) and
      protect["jwk"].has_key?("n")
      key     = protect["jwk"]["n"]
    end

    if @registered_keys.include?(key)
      true
    else
      {:status => 409,
        :headers => {
          "Location" => "#{@endpoint}/acme/reg/asdf",
          "Content-Type"=>"application/problem+json",
        },
        :body => "{\"type\":\"urn:acme:error:unauthorized\",\"detail\":\"No registration exists matching provided key\",\"status\":409}",
      }
    end

  end

  def do_bad_nonce(request)
    {:status => 409,
      :headers => {
        "Content-Type"=>"application/problem+json",
      },
      :body => "{\"type\":\"urn:acme:error:badNonce\",\"detail\":\"JWS has invalid anti-replay nonce\",\"status\":409}",
    }
  end

  def do_post_new_reg(request)
    req     = JSON.load(request.body)
    protect = JSON.load(Base64.urlsafe_decode64(req["protected"]))
    key = nil
    if protect.is_a?(Hash) and
      protect.has_key?("jwk") and
      protect["jwk"].is_a?(Hash) and
      protect["jwk"].has_key?("n")
      key     = protect["jwk"]["n"]
    end

    if @registered_keys.include?(key)
      {:status => 409,
        :headers => {
          "Location" => "#{@endpoint}/acme/reg/asdf",
          "Content-Type"=>"application/problem+json",
        },
        :body => "{\"type\":\"urn:acme:error:malformed\",\"detail\":\"Registration key is already in use\",\"status\":409}",
      }
    else
      @registered_keys << key unless key.nil?
      {:status => 201,
        :headers => {
          "Location" => "#{@endpoint}/acme/reg/asdf",
          "Link" => "<#{@endpoint}/acme/new-authz>;rel=\"next\",<#{@endpoint}/acme/terms>;rel=\"terms-of-service\""
        }
      }
    end
  end

  def do_post_new_authz(request)
    req     = JSON.load(request.body)

    result = do_check_key(req)
    return result unless result == true

    payload = JSON.load(Base64.urlsafe_decode64(req["payload"]))
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

    result = do_check_key(req)
    return result unless result == true

    sekrit  = @authz_template.extract(request.uri)["sekrit"]
    payload = JSON.load(Base64.urlsafe_decode64(req["payload"]))

    @http01_challenge[sekrit].merge!({
      "keyAuthorization" => payload["keyAuthorization"],
      "status" => "pending" })

    {:status => 200, :body => JSON.dump(@http01_challenge[sekrit]),  :headers => {"Content-Type" => "application/json"}}
  end

  def do_get_authz_challenges(request)
    sekrit = @authz_challenges_template.extract(request.uri)["sekrit"]

    body = {
      "status" => "valid",
      "validated" => Time.now,
      "expires" =>  (Date.today + 90).rfc3339,
      "identifier" => {
        "type": "dns",
        "value": @domain.name
      },

      "challenges" => [
        {
          "type" => "http-01",
          "status" => "valid",
          "uri" => "#{@endpoint}/authz/#{sekrit}/0",
          "token" => "alabaster"
        }
      ]

    }

    {:status => 200, :body => JSON.dump(body), :headers => {"Content-Type" => "application/json"}}
  end

  def do_get_authz_challenges_pending(request)
    sekrit = @authz_challenges_template.extract(request.uri)["sekrit"]

    body = {
      "status" => "pending",
      "validated" => Time.now,
      "expires" =>  (Date.today + 90).rfc3339,
      "identifier" => {
        "type": "dns",
        "value": @domain.name
      },

      "challenges" => [
        {
          "type" => "http-01",
          "status" => "pending",
          "uri" => "#{@endpoint}/authz/#{sekrit}/0",
          "token" => "alabaster"
        }
      ]

    }

    {:status => 200, :body => JSON.dump(body), :headers => {"Content-Type" => "application/json"}}
  end

  def do_get_authz_challenges_invalid(request)
    sekrit = @authz_challenges_template.extract(request.uri)["sekrit"]

    body = {
      "status" => "invalid",
      "validated" => Time.now,
      "expires" =>  (Date.today + 90).rfc3339,
      "identifier" => {
        "type": "dns",
        "value": @domain.name
      },

      "challenges" => [
        {
          "type" => "http-01",
          "status" => "invalid",
          "uri" => "#{@endpoint}/authz/#{sekrit}/0",
          "token" => "alabaster"
        }
      ]

    }

    {:status => 200, :body => JSON.dump(body), :headers => {"Content-Type" => "application/json"}}
  end

  def do_get_authz(request)
    sekrit = @authz_template.extract(request.uri)["sekrit"]

    @http01_challenge[sekrit].merge!({
      "status" => "valid",
      "validated" => Time.now,
      "expires" =>  (Date.today + 90).rfc3339})

    {:status => 200, :body => JSON.dump(@http01_challenge[sekrit]),  :headers => {"Content-Type" => "application/json"}}
  end

  def do_get_authz_pending(request)
    sekrit = @authz_template.extract(request.uri)["sekrit"]

    @http01_challenge[sekrit].merge!({"status" => "pending"})

    {:status => 200, :body => JSON.dump(@http01_challenge[sekrit]),  :headers => {"Content-Type" => "application/json"}}
  end

  def do_get_authz_invalid(request)
    sekrit = @authz_template.extract(request.uri)["sekrit"]

    @http01_challenge[sekrit].merge!({"status" => "invalid"})

    {:status => 200, :body => JSON.dump(@http01_challenge[sekrit]),  :headers => {"Content-Type" => "application/json"}}
  end

  def do_post_new_cert(request)
    req = JSON.load(request.body)

    result = do_check_key(req)
    return result unless result == true

    payload = JSON.load(Base64.urlsafe_decode64(req["payload"]))
    csr = OpenSSL::X509::Request.new(Base64.urlsafe_decode64(payload["csr"]))

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
    {:status => 200, :body => @root_ca_crt.to_s}
  end

  ####
  #
  # Tests start here.
  #
  #####

  def test_register
    omit unless @client

    result = @client.registered?
    assert(!result, "#registered? should return false if we're not registered yet")

    result = @client.register
    assert(result, "#register should return true")

    result = @client.registered?
    assert(result, "#registered? should return true once registered")

    assert_raise(Acme::Client::Error::Unauthorized, "#register should return raise an error on second attempt") { @client.register }
  end

  def test_verify
    omit unless @client
    @client.register

    result = nil
    result = @client.verify

    assert(result, "#verify should return true")
  end

  def test_request
    omit unless @client
    @client.register

    #
    # Give pending back a few times.
    #
    stub_request(:get,  @authz_template).
      to_return{|r| do_get_authz_pending(r)}.
      to_return{|r| do_get_authz_pending(r)}.
      to_return{|r| do_get_authz(r)}
    stub_request(:get,  @authz_challenges_template).
      to_return{|r| do_get_authz_challenges_pending(r)}
      to_return{|r| do_get_authz_challenges_pending(r)}
      to_return{|r| do_get_authz_challenges(r)}

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

  def test_register_with_duff_domains
    omit unless @client
    @client.register

    stub_request(:get,  @authz_template).
      to_return{|r| do_get_authz_pending(r)}.
      to_return{|r| do_get_authz_pending(r)}.
      to_return{|r| do_get_authz_invalid(r)}
    stub_request(:get,  @authz_challenges_template).
      to_return{|r| do_get_authz_challenges_pending(r)}
      to_return{|r| do_get_authz_challenges_pending(r)}
      to_return{|r| do_get_authz_challenges_invalid(r)}
    assert_nil(@client.request)

    @client.instance_variable_set(:@names, [])
    assert_nil(@client.request)
    assert_raise(ArgumentError){ @client.acme_certificate }
  end

  def test_register_when_first_name_fails_to_verify
    omit unless @client
    @client.register

    stub_request(:get,  @authz_template).
      to_return{|r| do_get_authz_invalid(r)}.
      to_return{|r| do_get_authz(r)}
    stub_request(:get,  @authz_challenges_template).
      to_return{|r| do_get_authz_challenges_invalid(r)}
      to_return{|r| do_get_authz_challenges(r)}

    req = @client.request

    assert_kind_of(OpenSSL::X509::Request, req)
    assert_equal("/CN=#{@domain.aliases.first}", req.subject.to_s)
  end

  def test_key
    omit unless @client
    assert_kind_of(OpenSSL::PKey::PKey, @client.key)
    assert_kind_of(OpenSSL::PKey::RSA,  @client.rsa_key)
  end

  def test_acme_certificate
    omit unless @client
    @client.register
    assert_kind_of(Acme::Client::Certificate, @client.acme_certificate)
  end

  def test_ssl_magic_works
    omit unless @client
    @domain.ssl_magic
  end

  def test_ssl_magic_breaks_nicely
    omit unless @client

    stub_request(:get,  @authz_template).
      to_return{|r| do_get_authz_invalid(r)}

    assert_raises(RuntimeError, "No error raised when an invalid request is generated"){ @domain.ssl_magic }
  end

  def test_bad_nonce_retries
    omit unless @client

    #
    # The client should retry "a reasonable" number of times.
    #
    stub_request(:post, "#{@endpoint}/acme/new-reg").
      to_return{|r| do_bad_nonce(r)}.
      to_return{|r| do_bad_nonce(r)}.
      to_return{|r| do_bad_nonce(r)}.
      to_return{|r| do_bad_nonce(r)}.
      to_return{|r| do_bad_nonce(r)}.
      to_return{|r| do_post_new_reg(r)}

      assert_nothing_raised{ @client.register }
  end

  #
  # This test gets run twice, with the DEBUG flag being flipped between runs.  Bit naughty really.
  #
  def test_challenge_file_cleanup
    #
    # Record the current DEBUG state so we can set it
    #
    old_debug = $DEBUG

    omit unless @client

    @client.register

    challenge_directory = "#{@prefix}/#{@domain}/public/htdocs/.well-known/acme-challenge"

    [false, true].each do |current_debug|

      #
      # Remove previous challenges
      #
      @http01_challenge = {}

      #
      # Now verify, setting/unsetting $DEBUG around it.
      #
      $DEBUG = current_debug
      @client.verify
      $DEBUG = old_debug

      @http01_challenge.each do |key, hash|

        fn = File.join(challenge_directory, hash["token"])

        if current_debug
          assert(File.exist?(fn),
            "#verify should not remove ACME challenge files when $DEBUG is set")
        else
          refute(File.exist?(fn),
            "#verify should remove ACME challenge files")
        end

      end

    end
  ensure
    #
    # If we barf, reset the DEBUG flag.
    #
    $DEBUG = old_debug
  end

end
