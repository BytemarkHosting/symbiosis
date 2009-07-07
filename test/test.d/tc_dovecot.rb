#!/usr/bin/ruby

require 'test/unit'
require 'net/imap'
require 'net/pop'
require 'bytemark/vhost/test/mail'

class TestDovecot < Test::Unit::TestCase

  def setup
    @domain = Bytemark::Vhost::Test::Mail.new()
    @domain.create

    @mailbox = @domain.add_mailbox("test")
    @mailbox.password = Bytemark::Vhost::Test.random_string
    
    @mailbox_crypt = @domain.add_mailbox("test_crypt")
    @mailbox_crypt.password = Bytemark::Vhost::Test.random_string
    @mailbox_crypt.crypt_password 

    Net::IMAP.debug = true if $DEBUG
  end

  def teardown
    @domain.destroy
  end

  def test_imap_capabilities
    capabilities = []
    assert_nothing_raised do
      imap = Net::IMAP.new('localhost', 143, false) 
      capabilities = imap.capability
      imap.disconnect unless imap.disconnected?
    end
    assert(capabilities.include?("IMAP4REV1"), "Server does not seem to support IMAP4REV1")
    assert(capabilities.include?("AUTH=PLAIN"), "Server does not seem to support PLAIN auth.")
    assert(capabilities.include?("AUTH=LOGIN"), "Server does not seem to support LOGIN auth.")
	  assert(capabilities.include?("STARTTLS"), "Server does not seem to support STARTTLS.")
  end

  def test_imap_auth_plain
    assert_nothing_raised do
      imap = Net::IMAP.new('localhost', 143, false) 
      imap.login(@mailbox.username, @mailbox.password)
      imap.logout
      imap.disconnect unless imap.disconnected?
    end
  end

  def test_imap_auth_login
    assert_nothing_raised do
      imap = Net::IMAP.new('localhost', 143, false) 
      imap.authenticate('LOGIN', @mailbox.username, @mailbox.password)
      imap.logout
      imap.disconnect unless imap.disconnected?
    end
  end

  def test_imap_auth_login_crypt
    assert_nothing_raised do
      imap = Net::IMAP.new('localhost', 143, false) 
      imap.authenticate('LOGIN', @mailbox_crypt.username, @mailbox_crypt.uncrypted_password)
      imap.logout
      imap.disconnect unless imap.disconnected?
    end
  end

  def test_imap_auth_tls
    # TODO: not implemented by net/imap library
  end
  
  def test_imap_auth_ssl
    assert_nothing_raised do
      imap = Net::IMAP.new('localhost', 993, true)
      imap.authenticate('LOGIN', @mailbox.username, @mailbox.password)
      imap.logout
      imap.disconnect unless imap.disconnected?
    end
  end

  def test_pop3_auth
    assert_nothing_raised do
      pop = Net::POP.new('localhost', 110)
      pop.set_debug_output STDOUT if $DEBUG
      pop.start(@mailbox.username, @mailbox.password)
      pop.finish
    end
  end

  def test_pop3_auth_crypt
    assert_nothing_raised do
      pop = Net::POP.new('localhost', 110)
      pop.set_debug_output STDOUT if $DEBUG
      pop.start(@mailbox_crypt.username, @mailbox_crypt.uncrypted_password)
      pop.finish
    end
  end

  def test_pop3_auth_tls
    # TODO: not implemented by net/pop library
  end

  def test_pop3_auth_ssl
    # TODO: not implemented by net/pop library
  end

end


