require 'test/unit'
require 'time'
require 'net/smtp'
require 'symbiosis/domain'
require 'symbiosis/domain/mailbox'

class TestEximLive < Test::Unit::TestCase

  def setup
    @domain = Symbiosis::Domain.new()
    @domain.create

    @mailbox = @domain.create_mailbox("test")
    @mailbox.encrypt_password = false
    @mailbox.password = Symbiosis::Utils.random_string

    @mailbox_crypt = @domain.create_mailbox("te-s.t_crypt")
    @mailbox_crypt.password = Symbiosis::Utils.random_string

    @ssl_ctx = OpenSSL::SSL::SSLContext.new("TLSv1_client")
    @ssl_ctx.verify_mode = OpenSSL::SSL::VERIFY_NONE

  end

  def teardown
    @domain.destroy unless $DEBUG
  end

  def fetch_test_user
    test_user = nil
    begin
      test_user = Etc.getpwnam("symbiosis-test")
    rescue ArgumentError
      # do nothing
    end
    test_user
  end

  def fetch_hostname
    if File.exist?('/proc/sys/kernel/hostname')
      File.read('/proc/sys/kernel/hostname').chomp
    else
      "localhost"
    end
  end

  def test_smtp_capabilities
    smtp = Net::SMTP.new('localhost', 25) 
    smtp.debug_output = $stdout if $DEBUG

    smtp.start do 
      assert(smtp.capable_starttls?,"STARTTLS is not advertised on port 25")
      assert(!smtp.capable_plain_auth?, "AUTH PLAIN advertised without TLS")
      assert(!smtp.capable_login_auth?, "AUTH LOGIN advertised without TLS")
    end

    smtp.enable_starttls( @ssl_ctx )
    smtp.start do 
        assert(smtp.capable_plain_auth?, "AUTH PLAIN not advertised after STARTTLS")
        assert(smtp.capable_login_auth?, "AUTH LOGIN not advertised after STARTTLS")
    end
  end

  def test_smtp_auth
    smtp = Net::SMTP.new('localhost', 25) 
    smtp.debug_output = $stdout if $DEBUG
    smtp.enable_starttls( @ssl_ctx )

    smtp.start do
      assert_nothing_raised("AUTH PLAIN failed for a user with plaintext password") do
        smtp.auth_login(@mailbox.username, @mailbox.password)
      end
    end

    smtp.start do
      assert_nothing_raised("AUTH LOGIN failed for a user with plaintext password") do
        smtp.auth_login(@mailbox.username, @mailbox.password)
      end
    end
  end

  def test_smtp_auth_local_user
    test_user = fetch_test_user
    return do_skip "No test user" if test_user.nil?

    hostname = fetch_hostname
    username = test_user.name + "@" + hostname
    password = Symbiosis::Utils.random_string

    File.open(File.join(test_user.dir,".password"),"w+"){|fh| fh.puts password}

    smtp = Net::SMTP.new('localhost', 25) 
    smtp.debug_output = $stdout if $DEBUG
    smtp.enable_starttls( @ssl_ctx )

    smtp.start do
      assert_nothing_raised("AUTH PLAIN failed for the local user") do
        smtp.auth_plain(username, password)
      end
    end

    smtp.start do
      assert_nothing_raised("AUTH LOGIN failed for the local user") do
        smtp.auth_login(username, password)
      end
    end
  end

  def test_smtp_auth_crypt
    smtp = Net::SMTP.new('localhost', 25) 
    smtp.debug_output = $stdout if $DEBUG
    smtp.enable_starttls( @ssl_ctx )

    smtp.start do
      assert_nothing_raised("AUTH PLAIN failed for a user with crypt'd password") do
        smtp.auth_login(@mailbox_crypt.username, @mailbox_crypt.password)
      end
    end

    smtp.start do
      assert_nothing_raised("AUTH PLAIN failed for a user with crypt'd password") do
        smtp.auth_login(@mailbox_crypt.username, @mailbox_crypt.password)
      end
    end
  end

  def test_ratelimiting
    smtp = Net::SMTP.new('localhost', 25)
    smtp.debug_output = $stdout if $DEBUG
    smtp.enable_starttls( @ssl_ctx )
    msg =<<EOF
Return-Path: #{@mailbox_crypt.username}
Envelope-To: #{@mailbox.username}
Date: #{Time.now.rfc2822}
From: #{@mailbox_crypt.username}
To: #{@mailbox.username}

Testing 1.2.3..
--
Symbiosis Test
EOF


    smtp.start do
      assert_nothing_raised("AUTH PLAIN failed for a user with crypt'd password") do
        smtp.auth_login(@mailbox_crypt.username, @mailbox_crypt.password)
      end

      assert_nothing_raised do
        3.times do
          smtp.send_message msg, @mailbox_crypt.username, @mailbox.username
        end
      end

      Symbiosis::Utils.set_param("mailbox-ratelimit","2",@domain.config_dir)

      assert_raise(Net::SMTPFatalError) do
        3.times do
          smtp.send_message msg, @mailbox_crypt.username, @mailbox.username
        end
      end

    end
  ensure
    10.times do
      break if `/usr/sbin/exiqgrep -i -f '#{@mailbox_crypt.username}'`.length == 0
      sleep 1
    end
  end

#  def do_test_deliver(mailbox)
#    sender_address = "postmaster@#{mailbox.domain.name}"
#    rcpt_address   = mailbox.username
#    msg =<<EOF
#Return-Path: #{sender_address}
#Envelope-To: #{rcpt_address}
#Date: #{Time.now.rfc2822}
#From: #{sender_address}
#To: #{rcpt_address}
#
#Testing 1.2.3..
#--
#Symbiosis Test
#EOF
#
#    do_dovecot_delivery(sender_address, rcpt_address, msg, 0, mailbox)
#
#    new_files = Dir.glob(File.join(mailbox.maildir, "new", "*")).length
#    assert_equal(1, new_files, "Found #{new_files} messages in Maildir/new rather than just 1")
#  end
#  
#  def do_setup_local_mailbox(test_user)
#    hostname = fetch_hostname
#    mailbox = Symbiosis::Domains.find_mailbox(test_user.name + "@" + hostname)
#
#    #
#    # AWOOGA.

#    #
#    FileUtils.rm_rf(mailbox.maildir)
#
#    return mailbox
#  end
#
#  def test_deliver
#    do_test_deliver(@mailbox)
#  end
#
#  def test_deliver_local_user
#    test_user = fetch_test_user
#    return do_skip "No test user" if test_user.nil?
#    mailbox = do_setup_local_mailbox(test_user)
#
#    do_test_deliver(mailbox)
#  end
#
#  def test_smtp_quotas
#    #
#    # SMTP quotas are done in units of kibibytes, apparently.
#    #
#    @mailbox.quota = "50ki"
#    assert_equal(51200, @mailbox.quota, "Mailbox quota not set correctly.")
#
#    quotaroot = nil
#    quota = nil
#
#    assert_nothing_raised do
#      smtp = Net::SMTP.new('localhost', 25, false)
#      smtp.authenticate('LOGIN', @mailbox.username, @mailbox.password)
#
#      #
#      # Now check the quotaroot.
#      #
#      qra = smtp.getquotaroot("INBOX")
#      quotaroot = qra.find{|q| q.is_a?(Net::SMTP::MailboxQuotaRoot)}
#
#      #
#      # And the quotas.
#      #
#      quota = qra.find{|q| q.is_a?(Net::SMTP::MailboxQuota)}
#
#      smtp.logout
#      smtp.disconnect unless smtp.disconnected?
#    end
#
#    assert_equal("INBOX", quotaroot.mailbox, "Quota root returned the wrong mailbox.")
#    assert_equal(["Symbiosis mailbox quota"], quotaroot.quotaroots, "Quota root returned the wrong set of quota roots.")
#    assert_equal("Symbiosis mailbox quota", quota.mailbox)
#    assert_equal(0, quota.usage.to_i)
#    assert_equal(50, quota.quota.to_i)
#  end
#
#  def do_test_deliver_with_quotas(mailbox)
#    #
#    # SMTP quotas are done in units of kibibytes, apparently.
#    #
#    mailbox.quota = "50ki"
#    assert_equal(51200, mailbox.quota, "Mailbox quota not set correctly.")
#
#    #
#    # An SMTP/POP3 login should trigger this normally.
#    #
#    @mailbox.rebuild_maildirsize
#
#    sender_address = "postmaster@#{mailbox.domain.to_s}"
#    rcpt_address   = mailbox.username
#    msg =<<EOF
#Return-Path: #{sender_address}
#Envelope-To: #{rcpt_address}
#Date: #{Time.now.rfc2822}
#From: #{sender_address}
#To: #{rcpt_address}
#
#Testing 1.2.3..
#--
#Symbiosis Test
#EOF
#
#    #
#    # A small message should go through just fine
#    #
#    do_dovecot_delivery(sender_address, rcpt_address, msg)
#
#    #
#    # Make sure we've got the right number of messages in new/
#    #
#    new_files = Dir.glob(File.join(mailbox.maildir, "new", "*")).length
#    assert_equal(1, new_files, "Found #{new_files} messages in Maildir/new rather than just 1")
#
#    #
#    # Now make our message unfeasably long
#    #
#    msg += "x"*mailbox.quota
#
#    #
#    # Deliver should return a temporary failure message.
#    #
#    do_dovecot_delivery(sender_address, rcpt_address, msg, 75)
#
#    #
#    # And nothing should be delivered.
#    #
#    new_files = Dir.glob(File.join(mailbox.maildir, "new", "*")).length
#    assert_equal(1, new_files, "Found #{new_files} messages in Maildir/new rather than just 1")
#  end
#  
#  def test_deliver_with_quotas
#    do_test_deliver_with_quotas(@mailbox)
#  end
#
#  def do_test_deliver_with_sieve(mailbox)
#    sieve =<<EOF
#require "fileinto";
#
#fileinto "testing";
#stop;
#EOF
#
#    # Write the file.
#    Symbiosis::Utils.set_param(mailbox.dot + "sieve", sieve, mailbox.directory)
#
#    sender_address = "postmaster@#{mailbox.domain.to_s}"
#    rcpt_address   = mailbox.username
#    msg =<<EOF
#Return-Path: #{sender_address}
#Envelope-To: #{rcpt_address}
#Date: #{Time.now.rfc2822}
#From: #{sender_address}
#To: #{rcpt_address}
#
#Testing 1.2.3..
#--
#Symbiosis Test
#EOF
#
#    #
#    # Now deliver our message
#    #
#    do_dovecot_delivery(sender_address, rcpt_address, msg, 0, mailbox)
#
#    #
#    # And nothing should be delivered to the inbox.
#    #
#    new_files = Dir.glob(File.join(mailbox.maildir, "new", "*")).length
#    assert_equal(0, new_files, "Found #{new_files} messages in Maildir/new rather than 0")
#
#    #
#    # It should be delivered to the "testing" box.
#    #
#    new_files = Dir.glob(File.join(mailbox.maildir, ".testing", "new", "*")).length
#    assert_equal(1, new_files, "Found #{new_files} messages in Maildir/.testing/new rather than just 1")
#  end
#
#  def test_deliver_with_sieve
#    @mailbox.create
#    do_test_deliver_with_sieve(@mailbox)
#  end
#
#  def test_deliver_with_sieve_for_local_users
#    test_user = fetch_test_user
#    return do_skip "No test user" if test_user.nil?
#    mailbox = do_setup_local_mailbox(test_user)
#    sieve_file = File.join(mailbox.directory, ".sieve")
#
#    do_test_deliver_with_sieve(mailbox)
#  ensure
#    File.unlink(sieve_file) if sieve_file and File.exist?(sieve_file)
#  end
#
#  def do_test_deliver_with_sieve_and_quota(mailbox)
#    mailbox.create
#    sieve =<<EOF
#require "fileinto";
#
#fileinto "testing";
#stop;
#EOF
#
#    # Write the file.
#    Symbiosis::Utils.set_param(mailbox.dot + "sieve", sieve, mailbox.directory)
#
#    sender_address = "postmaster@#{mailbox.domain.to_s}"
#    rcpt_address   = mailbox.username
#    msg =<<EOF
#Return-Path: #{sender_address}
#Envelope-To: #{rcpt_address}
#Date: #{Time.now.rfc2822}
#From: #{sender_address}
#To: #{rcpt_address}
#
#Testing 1.2.3..
#--
#Symbiosis Test
#EOF
#
#    #
#    # Now create a quota 
#    #
#    mailbox.quota = "5ki"
#    mailbox.rebuild_maildirsize
#    
#    # 
#    # And make our message VERY long.
#    # 
#    msg += "x"*mailbox.quota
#
#    #
#    # And try to deliver again, this should temp fail.
#    #
#    do_dovecot_delivery(sender_address, rcpt_address, msg, 75, mailbox)
#
#    #
#    # And nothing should be delivered.
#    #
#    new_files = Dir.glob(File.join(mailbox.maildir, ".testing", "new", "*")).length
#    assert_equal(0, new_files, "Found #{new_files} messages in Maildir/.testing/new rather than just 1 after the quota has been exceeded.")
#  end
#
#  def test_deliver_with_sieve_and_quota
#    do_test_deliver_with_sieve_and_quota(@mailbox)
#  end
#
#  #
#  # This is fugly, but required to drop privileges properly.
#  #
#  def do_dovecot_delivery(sender_address, rcpt_address, msg, expected_code=0, mailbox = @mailbox)
#    fork do 
#      #
#      # Drop privileges
#      #
#      if 0 == Process.uid
#        Process::Sys.setgid(mailbox.gid)
#        Process::Sys.setuid(mailbox.uid)
#      end
#
#      ENV.keys.each do |k|
#        ENV[k] = nil
#      end
#      
#      ENV['HOME'] = mailbox.directory
#      ENV['USER'] = mailbox.username
#
#      cmd = "/usr/lib/dovecot/deliver -e -k -f \"#{sender_address}\" -d \"#{rcpt_address}\""
#
#      IO.popen(cmd,"w+") do |pipe|
#        pipe.puts msg
#      end
#
#      exit $?.exitstatus
#    end
#
#    Process.wait
#
#    assert_equal(expected_code, $?.exitstatus, "Dovecot deliver failed with the wrong exit code (#{$?.to_i})")
#  end
#
#end
#

end
