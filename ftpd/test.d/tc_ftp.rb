#
#  Simple FTP test - create a new domain and attempt to login with the
# new credentials.
#

require 'symbiosis/domain/ftp'
require 'net/ftp'
require 'test/unit'
require 'pp'

class TestFTP < Test::Unit::TestCase

  def setup
    #
    #  Create the domain
    #
    @domain = Symbiosis::Domain.new()
    @domain.create()

  end

  def teardown
    #
    #  Delete the temporary domain
    #
    unless $DEBUG
      @domain.destroy()
    else
      puts "Domian configuration kept in #{@domain.directory}"
    end
  end
  
  def test_login_without_ftp_password
    #
    # Try logging in when no password has been set.
    #
    assert_raise(Net::FTPPermError, "FTP Login succeeded when FTP logins were not permitted.")  do
      Net::FTP.open('localhost') do |ftp|
        ftp.login( @domain.name, "some password here" )
      end
    end
  end

  def test_login_with_empty_password
    #
    # Try logging in when an empty file is in place.
    #
    FileUtils.touch(@domain.ftp_password_file)

    assert_raise(Net::FTPPermError, "FTP Login succeeded when FTP logins were not permitted.")  do
      Net::FTP.open('localhost') do |ftp|
        ftp.login( @domain.name, "" )
      end
    end
  end

  def test_logins
    #
    #  Set the password to a random string.
    #
    password = Symbiosis::Utils.random_string()

    #
    # Now test logins with both crypted and plain text passwords stored
    #
    [
      ["plain", password],
      ["crypt'd", "{CRYPT}"+password.crypt("$1$"+Symbiosis::Utils.random_string(8)+"$")]
    ].each do |crypted, password_data|

      Symbiosis::Utils.safe_open(@domain.ftp_password_file,"a+") do |f|
        f.truncate(0)
        f.puts password_data
      end

      assert_nothing_raised("FTP single user login failed with #{crypted} passwd.")  do
        Net::FTP.open('localhost') do |ftp|
          ftp.login( @domain.name, password )
        end
      end
    end
  end


  def test_new_logins
    #
    #  Set the password to a random string.
    #
    password = Symbiosis::Utils.random_string()

    #
    # Now test logins with both crypted and plain text passwords stored
    #
    [
      ["plain", password],
      ["crypt'd", "{CRYPT}"+password.crypt("$1$"+Symbiosis::Utils.random_string(8)+"$")]
    ].each do |crypted, password_data|

      Symbiosis::Utils.safe_open(@domain.ftp_users_file,"a+") do |f|
        f.truncate(0)
        f.puts Symbiosis::Domain::FTPUser.new("test",@domain,password, "test").to_s
      end

      username = "test@#{@domain.name}"

      assert_nothing_raised("FTP multi user login failed with #{crypted} passwd.")  do
        Net::FTP.open('localhost') do |ftp|
          ftp.login(username, password )
        end
      end
    end
  end


  def test_quota
    quota_file = File.join(@domain.config_dir,"ftp-quota")
    password_file = File.join(@domain.config_dir,"ftp-password")

    #
    # A password is required, or the quota is always nil.
    #
    Symbiosis::Utils.safe_open(password_file,"a+") do |f|
      f.truncate(0)
      f.puts Symbiosis::Utils.random_string
    end

    [[1e6, "1M\n"],
     [2.5e9, "2.5G\n"],
     [300,"300 \n"],
     [300e6,"300 M\n"]
    ].each do |expected,contents|
      #
      # Make sure no quota has been set.
      #
      File.unlink(quota_file) if File.exists?(quota_file)

      Symbiosis::Utils.safe_open(quota_file,"a+") do |f|
        f.truncate(0)
        f.puts contents
      end

      assert_equal(expected, @domain.ftp_quota)

      #
      # Delete it again
      #
      File.unlink(quota_file)
    end

  end

  def test_user_quota
    tests = [[1e6, "1M"],
     [2.5e9, "2.5G"],
     [300,"300 "],
     [300e6,"300 M"]]

    Symbiosis::Utils.safe_open(@domain.ftp_users_file,"a+") do |f|
      tests.each_with_index do |test,i|
        contents = test[1]
        f.puts "test#{i}:#{Symbiosis::Utils.random_string}::#{contents}"
      end
    end

    users = @domain.ftp_multi_users

    assert_equal(4, users.length)

    tests.each_with_index do |test,i|
      expected = test[0]
      assert_equal(expected, users[i].quota)
    end
  end
end
