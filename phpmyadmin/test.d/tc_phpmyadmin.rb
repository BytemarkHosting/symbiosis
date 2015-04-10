#
#  Simple tests of the PHPMyAdmin installation
#
require 'symbiosis/host'
require 'net/https'
require 'test/unit'

begin
  require 'mysql'
rescue LoadError
  # Do nothing.
end

class TestPhpMyAdmin < Test::Unit::TestCase

  @@ip = Symbiosis::Host.primary_ip.to_s

  def setup
    # NOP
  end

  def teardown
    # NOP
  end

  #
  #  Fetch the admin password
  #
  def root_passwd()
    if ( File.exist?( "/etc/symbiosis/.passwd" ) )
      File.read("/etc/symbiosis/.passwd").chomp
    else
      nil
    end
  end

  #
  #  Fetch the debian password
  #
  def debian_passwd()
    #
    # If there is no debian.cnf, give up now.
    #
    return nil unless File.exist?( "/etc/mysql/debian.cnf" )

    File.open("/etc/mysql/debian.cnf").each do |line|
      next unless line =~ /^\s*password\s*=\s*(\S+)/

      return $1
    end

    nil
  end

  #
  # Test that we redirected to the HTTPS site if we connect on port 80.
  #
  def test_phpmyadmin_http_redirect
    http         = Net::HTTP.new( @@ip, 80, nil )
    http.use_ssl = false

    # Get the contents
    http.start do |connection|
      request  = Net::HTTP::Get.new("/phpmyadmin/")
      response = connection.request(request)

      assert_equal(302, response.code.to_i, "No redirect when fetching /phpmyadmin/" )
      assert_match(/^https:/, response['location'], "Redirect to non-https site when when fetching /phpmyadmin/")
    end
  end

  #
  # Test that we get a 401 if we don't supply a username/password.
  #
  def test_phpmyadmin_requires_basic_authentication
    http     = Net::HTTP.new( @@ip, 443, nil )
    http.use_ssl   = true

    # disable "warning: peer certificate won't be verified in this SSL session."
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE

    # Get the contents
    http.start do |connection|
      request  = Net::HTTP::Get.new("/phpmyadmin/")
      response = connection.request(request)

      assert_equal(401, response.code.to_i, "Did not get '401 Unauthenticated' response when fetching /phpmyadmin/" )
    end
  end

  #
  # Make sure that if we don't give a root password, we *always* get 401
  # unauthenticated (even if no root password has been set) 
  #
  def test_root_login_fails_when_no_password_is_given
    http     = Net::HTTP.new( @@ip, 443, nil )
    http.use_ssl   = true

    # disable "warning: peer certificate won't be verified in this SSL session."
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE

    # Get the contents
    http.start do |connection|
      request  = Net::HTTP::Get.new("/phpmyadmin/")
      request.basic_auth "root", ""
      response = connection.request(request)
      assert_equal(401, response.code.to_i, "Phpmyadmin login for root succeeded when no password was given." )
    end
  end

  #
  # Now test that we succeed with the root username + password.
  #
  def test_root_login_succeeds
    #
    # Fetch the root password.
    #
    password = root_passwd()

    #
    # Check our username/password are correct.
    #
    ok = do_verify_mysql_user("root", password)
    if ok.nil?
      puts "\nSkipping phpmyadmin root auth test - password not found."
      return 
    elsif false == ok
      puts "\nSkipping phpmyadmin root auth test - incorrect password found."
      return
    end

    http     = Net::HTTP.new( @@ip, 443, nil )
    http.use_ssl   = true

    # disable "warning: peer certificate won't be verified in this SSL session."
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE

    # Get the contents
    http.start do |connection|
      request  = Net::HTTP::Get.new("/phpmyadmin/")
      request.basic_auth "root", password
      response = connection.request(request)
      assert_equal(200, response.code.to_i, "Phpmyadmin login failed for the root user." )
    end
  end

  #
  #  Test that logging in with the 'debian-sys-maint' user fails.
  #
  def test_debian_sys_maint_cannot_login
    #
    # Fetch the debian-sys-maint password
    #
    password = debian_passwd()
    
    #
    # Check our username/password are correct.
    #
    ok = do_verify_mysql_user("debian-sys-maint", password)
    if ok.nil?
      puts "\nSkipping phpmyadmin debian-sys-maint auth test - password not found."
      return 
    elsif false == ok
      puts "\nSkipping phpmyadmin debian-sys-maint auth test - incorrect password found."
      return
    end

    http     = Net::HTTP.new( @@ip, 443, nil )
    http.use_ssl   = true

    # disable "warning: peer certificate won't be verified in this SSL session."
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE

    # Get the contents
    http.start do |connection|
      request  = Net::HTTP::Get.new("/phpmyadmin/")
      request.basic_auth "debian-sys-maint", password

      response = connection.request(request)
      assert_equal(401, response.code.to_i, "Phpmyadmin login succeeded for the debian-sys-maint user." )
    end
  end

  ########################################################################

  #
  # This is a quick check to make sure the username/password work.
  #
  #  nil -> unable to check
  #  false -> check failed
  #  true -> check passed!
  #  
  def do_verify_mysql_user(username, password)
    #
    # If no username/password set, return nil.
    #
    if ( username.nil? or password.nil? )
      return nil

    #
    # Use the ruby Mysql library if available.
    #
    elsif defined? Mysql
      dbh = nil
      begin
        dbh = Mysql.new(nil, username, password)
        return true

      rescue Mysql::Error
        return false

      ensure
        dbh.close if dbh
      end      

    #
    # Failing that, try the mysql command line.
    #
    elsif File.executable?("/usr/bin/mysql")
      system("/usr/bin/mysql -u#{username} -p#{password} -e quit >/dev/null 2>&1")
      return $?.success?

    end

    #
    # If we get this far, return nil.  No check has taken place.
    #
    return nil
  end


end
