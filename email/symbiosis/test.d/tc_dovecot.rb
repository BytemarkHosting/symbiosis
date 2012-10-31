#!/usr/bin/ruby1.8

require 'test/unit'
require 'time'
require 'net/imap'
require 'net/pop'
require 'symbiosis/domain'
require 'symbiosis/domain/mailbox'

class TestDovecot < Test::Unit::TestCase

  def setup
    @domain = Symbiosis::Domain.new()
    @domain.create

    @mailbox = @domain.create_mailbox("test")
    @mailbox.encrypt_password = false
    @mailbox.password = Symbiosis::Utils.random_string

    @mailbox_crypt = @domain.create_mailbox("te-s.t_crypt")
    @mailbox_crypt.password = Symbiosis::Utils.random_string

    Net::IMAP.debug = true if $DEBUG
  end

  def teardown
    @domain.destroy unless $DEBUG
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
      imap.authenticate('LOGIN', @mailbox_crypt.username, @mailbox_crypt.password)
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
      pop.start(@mailbox_crypt.username, @mailbox_crypt.password)
      pop.finish
    end
  end

  def test_pop3_auth_tls
    # TODO: not implemented by net/pop library
  end

  def test_pop3_auth_ssl
    # TODO: not implemented by net/pop library
  end

  def test_deliver
    sender_address = "postmaster@#{@mailbox.domain.to_s}"
    rcpt_address   = @mailbox.username
    msg =<<EOF
Return-Path: #{sender_address}
Envelope-To: #{rcpt_address}
Date: #{Time.now.rfc2822}
From: #{sender_address}
To: #{rcpt_address}

Testing 1.2.3..
--
Symbiosis Test
EOF

    do_dovecot_delivery(sender_address, rcpt_address, msg)

    new_files = Dir.glob(File.join(@mailbox.maildir, "new", "*")).length
    assert_equal(1, new_files, "Found #{new_files} messages in Maildir/new rather than just 1")
  end
  
  def test_imap_quotas
    #
    # IMAP quotas are done in units of kibibytes, apparently.
    #
    @mailbox.quota = "50ki"
    assert_equal(51200, @mailbox.quota, "Mailbox quota not set correctly.")

    quotaroot = nil
    quota = nil

    assert_nothing_raised do
      imap = Net::IMAP.new('localhost', 143, false)
      imap.authenticate('LOGIN', @mailbox.username, @mailbox.password)

      #
      # Now check the quotaroot.
      #
      qra = imap.getquotaroot("INBOX")
      quotaroot = qra.find{|q| q.is_a?(Net::IMAP::MailboxQuotaRoot)}

      #
      # And the quotas.
      #
      quota = qra.find{|q| q.is_a?(Net::IMAP::MailboxQuota)}

      imap.logout
      imap.disconnect unless imap.disconnected?
    end

    assert_equal("INBOX", quotaroot.mailbox, "Quota root returned the wrong mailbox.")
    assert_equal(["Symbiosis mailbox quota"], quotaroot.quotaroots, "Quota root returned the wrong set of quota roots.")
    assert_equal("Symbiosis mailbox quota", quota.mailbox)
    assert_equal(0, quota.usage.to_i)
    assert_equal(50, quota.quota.to_i)
  end

  def test_deliver_with_quotas
    #
    # IMAP quotas are done in units of kibibytes, apparently.
    #
    @mailbox.quota = "50ki"
    assert_equal(51200, @mailbox.quota, "Mailbox quota not set correctly.")

    #
    # An IMAP/POP3 login should trigger this normally.
    #
    @mailbox.rebuild_maildirsize

    sender_address = "postmaster@#{@mailbox.domain.to_s}"
    rcpt_address   = @mailbox.username
    msg =<<EOF
Return-Path: #{sender_address}
Envelope-To: #{rcpt_address}
Date: #{Time.now.rfc2822}
From: #{sender_address}
To: #{rcpt_address}

Testing 1.2.3..
--
Symbiosis Test
EOF

    #
    # A small message should go through just fine
    #
    do_dovecot_delivery(sender_address, rcpt_address, msg)

    #
    # Make sure we've got the right number of messages in new/
    #
    new_files = Dir.glob(File.join(@mailbox.maildir, "new", "*")).length
    assert_equal(1, new_files, "Found #{new_files} messages in Maildir/new rather than just 1")

    #
    # Now make our message unfeasably long
    #
    msg += "x"*@mailbox.quota

    #
    # Deliver should return a temporary failure message.
    #
    do_dovecot_delivery(sender_address, rcpt_address, msg, 75)

    #
    # And nothing should be delivered.
    #
    new_files = Dir.glob(File.join(@mailbox.maildir, "new", "*")).length
    assert_equal(1, new_files, "Found #{new_files} messages in Maildir/new rather than just 1")

  end

  def test_deliver_with_sieve
    @mailbox.create
    sieve =<<EOF
require "fileinto";

fileinto "testing";
stop;
EOF

    # Write the file.
    Symbiosis::Utils.set_param("sieve", sieve, @mailbox.directory)


    sender_address = "postmaster@#{@mailbox.domain.to_s}"
    rcpt_address   = @mailbox.username
    msg =<<EOF
Return-Path: #{sender_address}
Envelope-To: #{rcpt_address}
Date: #{Time.now.rfc2822}
From: #{sender_address}
To: #{rcpt_address}

Testing 1.2.3..
--
Symbiosis Test
EOF

    #
    # Now deliver our message
    #
    do_dovecot_delivery(sender_address, rcpt_address, msg)

    #
    # And nothing should be delivered to the inbox.
    #
    new_files = Dir.glob(File.join(@mailbox.maildir, "new", "*")).length
    assert_equal(0, new_files, "Found #{new_files} messages in Maildir/new rather than 0")

    #
    # It should be delivered to the "testing" box.
    #
    new_files = Dir.glob(File.join(@mailbox.maildir, ".testing", "new", "*")).length
    assert_equal(1, new_files, "Found #{new_files} messages in Maildir/.testing/new rather than just 1")

    #
    # Now create a quota 
    #
    @mailbox.quota = "5ki"
    @mailbox.rebuild_maildirsize
    
    # 
    # And make our message VERY long.
    # 
    msg += "x"*@mailbox.quota

    #
    # And try to deliver again, this should temp fail.
    #
    do_dovecot_delivery(sender_address, rcpt_address, msg, 75)

    #
    # And nothing should be delivered.
    #
    new_files = Dir.glob(File.join(@mailbox.maildir, ".testing", "new", "*")).length
    assert_equal(1, new_files, "Found #{new_files} messages in Maildir/.testing/new rather than just 1 after the quota has been exceeded.")
  end

  def do_dovecot_delivery(sender_address, rcpt_address, msg, expected_code=0)
    begin
      #
      # Drop privileges
      #
      if 0 == Process.uid
        Process::Sys.setegid(@domain.gid)
        Process::Sys.seteuid(@domain.uid)
      end

      %w(HOME).each do |e|
        ENV["OLD_#{e}"] = ENV[e]
      end
      ENV['HOME'] = @mailbox.directory

      cmd = "/usr/lib/dovecot/deliver -k -s -f \"#{sender_address}\" -a \"#{rcpt_address}\""

      IO.popen(cmd,"w+") do |pipe|
        pipe.puts msg
      end

      assert_equal(expected_code, $?.exitstatus, "Dovecot deliver failed with the wrong exit code (#{$?.to_i})")
    ensure
      #
      # Restore back to root.
      #
      if 0 == Process.uid
        Process::Sys.seteuid(0)
        Process::Sys.setegid(0)
      end

      %w(HOME).each do |e|
        ENV[e] = ENV["OLD_#{e}"]
      end
    end
  end

end


