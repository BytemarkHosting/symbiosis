#
#  Simple FTP test - create a new domain and attempt to login with the
# new credentials.
#

require 'symbiosis/domain/ftp'
require 'net/ftp'
require 'test/unit'

class TestFTP < Test::Unit::TestCase

  def setup
    #
    #  Create the domain
    #
    @domain = Symbiosis::Domain.new()
    @domain.create()

    #
    #  Set the password to a random string.
    #
    @domain.ftp_password = Symbiosis::Utils.random_string()
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

  def test_login
    #
    #  Attempt a login, and report on the success.
    #
    assert_nothing_raised("Login failed") do
      Net::FTP.open('localhost') do |ftp|
        ftp.login( @domain.name, @domain.ftp_password )
      end
    end
  end


  def test_quota
    quota_file = File.join(@domain.config_dir,"ftp-quota")

    [[1e6, "1M\n"],
     [2.5e9, "2.5G\n"],
     [300,"300 \n"],
     [300e6,"300 M\n"]
    ].each do |expected,contents|
      #
      # Make sure no quota has been set.
      #
      File.unlink(quota_file) if File.exists?(quota_file)
      @domain.ftp_quota = nil

      File.open(quota_file,"w") do |fh|
        fh.print contents
      end

      assert_equal(expected, @domain.ftp_quota)

      #
      # Delete it again
      #
      File.unlink(quota_file)

      #
      # Set the contents
      #
      @domain.ftp_quota = contents

      new_contents = File.read(quota_file)
      assert_equal(contents, new_contents)
    end

  end

end
