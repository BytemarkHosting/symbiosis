#!/usr/bin/ruby
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
    @domain.destroy()
  end

  def test_login
    #
    #  Attempt a login, and report on the success.
    #
    assert_nothing_raised("Login failed") do
      Net::FTP.open('localhost') do |ftp|
        ftp.login( @domain.name, @domain.password )
      end
    end
  end
end
