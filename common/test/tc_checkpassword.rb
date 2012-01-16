#!/usr/bin/ruby

require 'test/unit'
require 'symbiosis/test/domain'

class TestCheckpassword < Test::Unit::TestCase

  def setup
    @domain = Symbiosis::Domain.new()
    @domain.create
  end

  def teardown
    @domain.destroy
  end

  def do_checkpassword_test(username, password)
    # this is horrid.
    op = ""
    IO.popen("checkpassword 3<&0 4>&1", "w+") do |p| 
      p.print "#{username}\0#{password}\0\0"
      p.close_write
      op = p.read
    end
    [op, $?.exitstatus]
  end

  def userdb_string(mailbox)
    ["userdb_user=#{mailbox.domain.user}",
     "userdb_home=#{mailbox.directory}",
     "userdb_uid=#{Etc.getpwnam(mailbox.domain.user).uid}",
     "userdb_gid=#{Etc.getpwnam(mailbox.domain.user).gid}",
     "userdb_mail=maildir:#{mailbox.directory}/Maildir", 
     ""].join("\t")
  end

  def test_checkpassword
    msg = nil
    status = nil
    mailbox = @domain.add_mailbox("test_-12311.testeything")
    mailbox.password = Symbiosis::Test.random_string

    assert_nothing_raised{ msg, status = do_checkpassword_test(mailbox.username, mailbox.password) }
    assert_equal(0, status)
    assert_equal(userdb_string(mailbox), msg)
   
    # Test for a malicious name.
    assert_nothing_raised{ msg, status = do_checkpassword_test("../"+mailbox.username, mailbox.password) }
    assert_equal(1, status)
    
    # Test for crypted passwords
    mailbox.crypt_password
    assert_nothing_raised{ msg, status = do_checkpassword_test(mailbox.username, mailbox.uncrypted_password) }
    assert_equal(0, status)
    assert_equal(userdb_string(mailbox), msg)
  end

  def test_checkpassword_empty
    msg = nil
    status = nil
    mailbox = @domain.add_mailbox("test")
    mailbox.password = ""

    assert_nothing_raised{ msg, status = do_checkpassword_test(mailbox.username, mailbox.password) }
    assert_equal(1, status, msg)

    mailbox.crypt_password
    assert_nothing_raised{ msg, status = do_checkpassword_test(mailbox.username, mailbox.uncrypted_password) }
    assert_equal(1, status, msg)
  end

  def test_checkpassword_none
    msg = nil
    status = nil
    mailbox = @domain.add_mailbox("test")

    assert_nothing_raised{ msg, status = do_checkpassword_test(mailbox.username, "") }
    assert_equal(1, status, msg)
  end
end


