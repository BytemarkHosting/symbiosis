#!/usr/bin/ruby
#
#  Simple tests of the PHPMyAdmin installation
#
#


require 'symbiosis/test/http'
require 'net/http'
require 'net/https'
require 'socket'
require 'test/unit'

class TestHTTP < Test::Unit::TestCase

  def setup
	# NOP
	@ip = IP()

	@username = "root"
	@password = passwd()
  end

  def teardown
	# NOP
  end

  #
  #  Fetch our main external IP address.  We need this because our
  # SSL site(s) only listen externally.
  #
  def IP()
    ip=""
    `ifconfig eth0 | grep 'inet addr:'`.split("\n").each do |line|
      if ( /([0-9]+)\.([0-9]+)\.([0-9]+)\.([0-9]+)/i.match( line ) )
        ip=$1 + "." + $2 + "." + $3 + "." + $4
      end
    end
    ip
  end


  #
  #  Fetch the admin password
  #
  def passwd()
      if ( File.exists?( "/etc/symbiosis/.passwd" ) )
        `cat /etc/symbiosis/.passwd`.chop
      else
	nil
      end
  end


  #
  # Test that we can get the PHPMyAdmin page.
  #
  def test_raw_http_phpmyadmin
      assert_nothing_raised("test that http://localhost/phpmyadmin redirects to SSL") do

	    http             = Net::HTTP.new( @ip, 80 )
	    http.use_ssl     = false

	    # Get the contents
	    http.start do |http|
	      request  = Net::HTTP::Get.new("/phpmyadmin/")
	      response = http.request(request)


              assert( response.code.to_i == 302, "We received a redirect when fetching /phpmyadmin/" )
	    end
      end
  end



  #
  # Test that we can get the PHPMyAdmin page.
  #
  def test_raw_https_phpmyadmin
      assert_nothing_raised("test that httpS://localhost/phpmyadmin prompts for auth") do

	    http             = Net::HTTP.new( @ip, 443 )
	    http.use_ssl     = true

	    # disable "warning: peer certificate won't be verified in this SSL session."
	    http.verify_mode = OpenSSL::SSL::VERIFY_NONE

	    # Get the contents
	    http.start do |http|
	      request  = Net::HTTP::Get.new("/phpmyadmin/")
	      response = http.request(request)
puts response.code.to_i

              assert( response.code.to_i == 401, "We received an 'unauthenticated' response when fetching /phpmyadmin/" )
	    end
      end
 end

  #
  # Now test that we succeed when using a username + password.
  #
  def test_auth_https_phpmyadmin

      if ( @password.nil? )
      	 puts "Avoiding test - cannot determine root password for MySQL"
	 return
      end

      assert_nothing_raised("test that httpS://localhost/phpmyadmin accepts a valid login") do

	    http             = Net::HTTP.new( @ip, 443 )
	    http.use_ssl     = true

	    # disable "warning: peer certificate won't be verified in this SSL session."
	    http.verify_mode = OpenSSL::SSL::VERIFY_NONE

	    # Get the contents
	    http.start do |http|
	      request  = Net::HTTP::Get.new("/phpmyadmin/")
	      request.basic_auth @username, @password

	      response = http.request(request)
	      assert( response.code.to_i == 200, "Logging in with the valid username/password works" )
	    end
      end
  end


end
