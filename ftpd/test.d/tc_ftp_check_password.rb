require 'test/unit'
require 'tmpdir'
require 'symbiosis/domain'
require 'symbiosis/domain/ftp'

class TestFtpdCheckPassword < Test::Unit::TestCase

  def setup
    @prefix = Dir.mktmpdir("srv","/tmp")
    @domain = Symbiosis::Domain.new(nil, @prefix)
    @domain.create
  end

  def teardown
    @domain.destroy unless @domain.nil?

    #
    # Remove the @prefix directory
    #
    FileUtils.remove_entry_secure @prefix
  end

  def do_checkpassword_test(username, password)
    # this is horrid.
    checkpassword = nil
    #
    # Are we in the source directory?
    #
    %w(../sbin/ /usr/sbin).each do |path|
      checkpassword = File.join(File.expand_path(path),"symbiosis-ftpd-check-password")
      break if File.executable?(checkpassword)
    end

    env = {
      "AUTHD_REMOTE_IP" => "23.34.45.56",
      "AUTHD_ACCOUNT" => username,
      "AUTHD_PASSWORD" => password.to_s
    }

    op = ""
    IO.popen(env, "RUBYLIB=#{$:.join(":")} #{checkpassword} --prefix #{@prefix} 2>/dev/null", "w+") do |p| 
      op = p.read
    end
    [op.split, $?.exitstatus]
  end

  def auth_array(dir="#{@domain.public_dir}/./", quota=nil)
    arr = ["auth_ok:1",
      "uid:#{Etc.getpwnam(@domain.user).uid}",
      "gid:#{Etc.getpwnam(@domain.user).gid}",
      "dir:#{dir}" ]
    if quota
      arr << "user_quota_size:#{quota}"
    end
    arr << "end"
    arr
  end

  def test_checkpassword_for_domain
    msg = nil
    status = nil
    pw = Symbiosis::Utils.random_string
    File.open(File.join(@domain.config_dir,"ftp-password"),"w+"){|fh| fh.puts(pw)}

    assert_nothing_raised{ msg, status = do_checkpassword_test(@domain.name, pw) }
    assert_equal(0, status, "Authentication failed for the correct password when the source is plain text")
    assert_equal(auth_array(),msg)

    # Now test crypt'd passwords
    crypt_pw = @domain.crypt_password(pw)
    File.open(File.join(@domain.config_dir,"ftp-password"),"w+"){|fh| fh.puts(crypt_pw)}
    assert_nothing_raised{ msg, status = do_checkpassword_test(@domain.name, pw) }
    assert_equal(0, status, "Authentication failed for the correct password when the source is plain text")
    assert_equal(auth_array(),msg)
  end

  def test_checkpassword_empty
    msg = nil
    status = nil
    File.open(File.join(@domain.config_dir,"ftp-password"),"w+"){|fh| fh.puts("")}

    assert_nothing_raised{ msg, status = do_checkpassword_test(@domain.name, "") }
    assert_equal(111, status, msg)
  end

  def test_checkpassword_none
    msg = nil
    status = nil

    assert_nothing_raised{ msg, status = do_checkpassword_test(@domain.name, "") }
    assert_equal(1, status, msg)
  end

  def test_checkpassword_newstyle
    msg = nil
    status = nil
    user = Symbiosis::Utils.random_string
    pw   = Symbiosis::Utils.random_string

    ftp_users_string = "#{user}:#{pw}:#{@domain.directory}:100M"

    File.open(File.join(@domain.config_dir,"ftp-users"),"w+"){|fh| fh.puts(ftp_users_string)}

    assert_nothing_raised{ msg, status = do_checkpassword_test("#{user}@#{@domain.name}", pw) }
    assert_equal(0, status, "Authentication failed for the correct password when the source is plain text")
    #
    #
    
    assert_equal(auth_array(@domain.directory,100000000),msg)
  end

end


