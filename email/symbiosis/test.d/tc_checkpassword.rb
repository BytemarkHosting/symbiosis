#!/usr/bin/ruby

require 'test/unit'
require 'symbiosis/domain'
require 'symbiosis/domain/mailbox'

class TestCheckpassword < Test::Unit::TestCase

  def setup
    @domain = Symbiosis::Domain.new()
    @domain.create
  end

  def teardown
    @domain.destroy unless @domain.nil?
  end

  def do_checkpassword_test(username, password)
    # this is horrid.
    checkpassword = nil
    #
    # Are we in the source directory?
    #
    %w(../../sbin/ /usr/sbin).each do |path|
      checkpassword = File.join(File.expand_path(path),"symbiosis-check-mailbox-password")
      break if File.executable?(checkpassword)
    end
    op = ""
    IO.popen("RUBYLIB=#{$:.join(":")} #{checkpassword} env 3<&0 4>&1 2>/dev/null", "w+") do |p| 
      p.print "#{username}\0#{password}\0\0"
      p.close_write
      op = p.read
    end
    [op.split, $?.exitstatus]
  end

  def userdb_array(mailbox)
     ["userdb_gid=#{Etc.getpwnam(mailbox.domain.user).gid}",
     "userdb_home=#{mailbox.directory}",
     "userdb_mail=maildir:#{mailbox.directory}/Maildir", 
     "userdb_uid=#{Etc.getpwnam(mailbox.domain.user).uid}",
     "userdb_user=#{mailbox.username}"]
  end

  def test_checkpassword
    msg = nil
    status = nil
    pw = Symbiosis::Utils.random_string
    mailbox = @domain.create_mailbox("test")
    mailbox.encrypt_password = false
    mailbox.password = pw

    assert_nothing_raised{ msg, status = do_checkpassword_test(mailbox.username, pw) }
    assert_equal(0, status)
    userdb_array(mailbox).each do |val|
      assert(msg.include?(val), "Environment did not contain #{val}")
    end
   
    # Test for a malicious name.
    assert_nothing_raised{ msg, status = do_checkpassword_test("../"+mailbox.username, pw) }
    assert_equal(1, status)
    
    # Test for crypted passwords
    mailbox.encrypt_password = true
    mailbox.password = pw
    assert_nothing_raised{ msg, status = do_checkpassword_test(mailbox.username, pw) }
    assert_equal(0, status)
    userdb_array(mailbox).each do |val|
      assert(msg.include?(val), "Environment did not contain #{val}")
    end
  end

  def test_checkpassword_empty
    msg = nil
    status = nil
    mailbox = @domain.create_mailbox("test")
    mailbox.password = ""

    assert_nothing_raised{ msg, status = do_checkpassword_test(mailbox.username, "") }
    assert_equal(111, status, msg)

    mailbox.encrypt_password = true
    mailbox.password = ""
    assert_nothing_raised{ msg, status = do_checkpassword_test(mailbox.username, "") }
    assert_equal(111, status, msg)
  end

  def test_checkpassword_none
    msg = nil
    status = nil
    mailbox = @domain.create_mailbox("test")

    assert_nothing_raised{ msg, status = do_checkpassword_test(mailbox.username, "") }
    assert_equal(111, status, msg)
  end
end


