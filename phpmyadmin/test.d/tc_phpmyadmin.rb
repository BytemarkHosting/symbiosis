#
#  Simple tests of the PHPMyAdmin installation
#
#
require 'symbiosis/host'
require 'net/http'
require 'net/https'
require 'socket'
require 'test/unit'

class TestPhpMyAdmin < Test::Unit::TestCase

  def setup
    @ip = Symbiosis::Host.primary_ip.to_s

    # Username we expect to find
    @username = "root"
    @password = passwd()

    # user setup by mysql-server*
    @debian_user = "debian-sys-maint"
    @debian_pass = debian_passwd()
  end

  def teardown
	# NOP
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
  #  Fetch the debian password
  #
  def debian_passwd()
    pass = nil

    if ( File.exists?( "/etc/mysql/debian.cnf" ) )

      File.open("/etc/mysql/debian.cnf").each do |line|
        if ( line =~ /password\s*=\s*(\S+)/  )
          pass = $1.dup
        end
      end
    end

    pass
  end


  #
  # Ensure there is a sane password in the Debian-specific MySQL configuration file
  #
  def test_debian_passwd
     assert( File.exists?( "/etc/mysql/debian.cnf" ), "There is a debian password file present" )
     assert( !debian_passwd().nil?, "Reading a password succeeded.  [We got #{debian_passwd()}" )
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


  #
  #  Test that logging in with the 'debian-sys-maint' user fails.
  #
  def test_disabled_user
      assert_nothing_raised("test that https://localhost/phpmyadmin denies the Debian user") do

	    http             = Net::HTTP.new( @ip, 443 )
	    http.use_ssl     = true

	    # disable "warning: peer certificate won't be verified in this SSL session."
	    http.verify_mode = OpenSSL::SSL::VERIFY_NONE

	    # Get the contents
	    http.start do |http|
	      request  = Net::HTTP::Get.new("/phpmyadmin/")
	      request.basic_auth @debian_user, @debian_pass

	      response = http.request(request)
              assert( response.code.to_i == 401, "Login failed for the 'debian-sys-maint' user." )
	    end
      end
 end


end
