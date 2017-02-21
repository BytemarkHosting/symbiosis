require 'symbiosis/email/poppass_handler'
require 'socket'
require 'test/unit'
require 'tmpdir'
require 'tempfile'
require 'eventmachine'
require 'syslog'
require 'socket'

class TestEmailPoppassClient < EventMachine::Connection
  attr_reader :script, :result

  def initialize(q,r)
    @script = q
    @result = r
  end

  def receive_data(l)
    @result << l.chomp

    unless script.empty?
      msg = script.shift
      send_data(msg+"\r\n") 
    end
  end

  def unbind
    EM.stop
  end

end

class TestEmailPoppassd < Test::Unit::TestCase

  def setup
    @prefix = Dir.mktmpdir("srv")
    File.chown(1000,1000,@prefix)

    @domains = []

    @syslog = Syslog.open( File.basename($0), Syslog::LOG_NDELAY, Syslog::LOG_MAIL )

    Symbiosis::Email::PoppassHandler.prefix = @prefix
    Symbiosis::Email::PoppassHandler.syslog = @syslog
    @sock = File.join(@prefix, File.basename($0)+"-#{$$}.sock")
    
    domain = Symbiosis::Domain.new(nil, @prefix)
    domain.create
    @mailbox = domain.create_mailbox("aarvo")
  end

  def teardown
    #
    #  Delete the temporary domain
    #
    @domains.each{|d| d.destroy() unless d.nil? }

    #
    # Remove the @prefix directory
    #
    FileUtils.remove_entry_secure @prefix

    @syslog.close
  end

  #
  # Not sure if this is a good thing to do.
  #
  def eventmachine(timeout = 30)
    Timeout::timeout(timeout) do
      #
      # Catch all eventmachine errors
      #
      EM.error_handler{ |e|
        flunk (["Error raised during EM loop: #{e.message}: #{e.to_s}"]+e.backtrace).join("\n")
      }

      EM.epoll
      EM.run do
        yield
      end
    end
  rescue Timeout::Error
    flunk 'Eventmachine was not stopped before the timeout expired'
  end

  require 'stringio'

  def do_test_script(script)
    result = []
    self.eventmachine do
      server  = EM.start_server("localhost", 0, Symbiosis::Email::PoppassHandler, 0)
      port    = Socket.unpack_sockaddr_in( EM.get_sockname( server )).first
      client  = EM.connect("localhost", port, TestEmailPoppassClient, script, result)
    end

    return result
  end

  def test_login_and_change
    @mailbox.password = "abc"
    assert @mailbox.login("abc")

    new_password = " this is a super secure password."

    results = do_test_script(["USER #{@mailbox.username}", "PASS abc", "NEWPASS #{new_password}", "QUIT"])

    # we should get back 200 (hello), 300 (please log in), 200 (authd), 200 (changed), 200 (bye)
    expected_results = [/^2\d\d /, /^3\d\d /, /^2\d\d/, /^2\d\d /, /^2\d\d /]

    results.zip(expected_results).each do |r, e|
      assert_match e, r
    end

    # now see if we can log in.
    assert(!@mailbox.login("abc"))
    assert(@mailbox.login(new_password))
  end

  def test_login_with_empty_password
    results = do_test_script(["USER #{@mailbox.username}", "PASS abc","QUIT"])

    # we should get back 200 (hello), 300 (please log in), 500 (failed), 200 (bye)
    expected_results = [/^2\d\d /, /^3\d\d /, /^5\d\d/, /^2\d\d /]

    results.zip(expected_results).each do |r, e|
      assert_match e, r
    end

  end
  
  def test_login_with_nonexistent_user
    results = do_test_script(["USER nobody@#{@mailbox.domain.name}", "PASS abc","QUIT"])

    # we should get back 200 (hello), 300 (please log in), 500 (failed), 200 (bye)
    expected_results = [/^2\d\d /, /^3\d\d /, /^5\d\d/, /^2\d\d /]

    results.zip(expected_results).each do |r, e|
      assert_match e, r
    end
  end

  def test_change_with_no_login
    @mailbox.password = "abc"

    results = do_test_script(["USER nobody@#{@mailbox.domain.name}", "NEWPASS abc", "QUIT"])
    # we should get back 200 (hello), 300 (password please), 400 (temp fail), 200 (bye)
    expected_results = [/^2\d\d /, /^3\d\d/, /^4\d\d /, /^2\d\d /]

    results.zip(expected_results).each do |r, e|
      assert_match e, r
    end
  end

  def test_weak_pasword
    @mailbox.password = "abc"
    assert @mailbox.login("abc")

    new_password = "typewriter"

    results = do_test_script(["USER #{@mailbox.username}", "PASS abc", "NEWPASS #{new_password}", "QUIT"])

    # we should get back 200 (hello), 300 (please log in), 200 (authd), 400 (temp fail), 200 (bye)
    expected_results = [/^2\d\d /, /^3\d\d /, /^2\d\d/, /^4\d\d /, /^2\d\d /]

    results.zip(expected_results).each do |r, e|
      assert_match e, r
    end

    # now make sure the password hasn't changed.
    assert(@mailbox.login("abc"))
    assert(!@mailbox.login(new_password))
  end

  def do_skip(msg)
    if self.respond_to?(:skip)
      skip msg
    elsif self.respond_to?(:omit)
      omit msg
    else
      puts "Skipping #{self.method_name} -- #{msg}"
    end
    return nil
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

  def test_shell_user
    test_user = fetch_test_user
    do_skip "No test user" if test_user.nil?

    hostname = ENV["HOSTNAME"] || Symbiosis::Host.fqdn
    #
    # Create the domain
    #
    domain = Symbiosis::Domain.new(hostname, @prefix)
    domain.create

    mailbox = Symbiosis::Domains.find_mailbox(test_user.name + "@" + hostname, @prefix)
    mailbox.create

    # do the test twice, with and without the hostname
    [test_user.name, mailbox.username].each do |username|
      old_password = "abc"
      mailbox.password = old_password
      assert(mailbox.login(old_password))
      new_password = " this is a super secure password."

      results = do_test_script(["USER #{username}", "PASS #{old_password}", "NEWPASS #{new_password}", "QUIT"])

      # we should get back 200 (hello), 300 (please log in), 200 (authd), 200 (changed), 200 (bye)
      expected_results = [/^2\d\d /, /^3\d\d /, /^2\d\d/, /^2\d\d /, /^2\d\d /]

      results.zip(expected_results).each do |r, e|
        assert_match e, r, "Unexpected output when using #{username}"
      end

      # now see if we can log in.
      assert(!mailbox.login(old_password))
      assert(mailbox.login(new_password))
    end

  end
end

