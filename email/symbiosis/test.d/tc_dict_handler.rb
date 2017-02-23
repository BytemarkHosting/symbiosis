require 'symbiosis/email/dict_handler'
require 'socket'
require 'test/unit'
require 'tmpdir'
require 'tempfile'
require 'eventmachine'
require 'syslog'
require 'json'

class TestEmailDictClient < EventMachine::Connection
  attr_reader :script, :result

  def initialize(q,r)
    @script = q
    @result = r
    msg = script.shift
    puts msg if $DEBUG
    send_data(msg+"\r\n")

  end

  def receive_data(l)
    puts l if $DEBUG
    @result << l.chomp

    unless script.empty?
      msg = script.shift
      puts msg if $DEBUG
      send_data(msg+"\r\n") 

    end
  end

  def unbind
    EM.stop
  end

end

class TestEmailDictd < Test::Unit::TestCase

  def setup
    @prefix = Dir.mktmpdir("srv")

    File.chown(1000,1000,@prefix)

    @domains = []

    @syslog = Syslog.open( File.basename($0), Syslog::LOG_NDELAY, Syslog::LOG_MAIL )

    Symbiosis::Email::DictHandler.prefix = @prefix
    Symbiosis::Email::DictHandler.syslog = @syslog
    
    @domain = Symbiosis::Domain.new(nil, @prefix)
    @domain.create
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
      server  = EM.start_server("localhost", 0, Symbiosis::Email::DictHandler, 0)
      port    = Socket.unpack_sockaddr_in( EM.get_sockname( server )).first
      client  = EM.connect("localhost", port, TestEmailDictClient, script, result)
    end

    return result
  end

  def test_virtual_user
    mailbox = @domain.create_mailbox("aarvo")
    mailbox.password = "abc"
    mailbox.quota = "1M"

    results = do_test_script(["L /passdb/#{mailbox.username}"])

    assert_equal("O", results.first[0])

    hash = {}

    assert_nothing_raised do
      hash = JSON.load(results.first[1..-1])
    end

    assert_equal(mailbox.username, hash['userdb_user'])
    assert_equal(mailbox.directory, hash["userdb_home"])
    assert_equal(mailbox.uid, hash["userdb_uid"])
    assert_equal(mailbox.gid, hash["userdb_gid"])
    assert_equal("maildir:"+mailbox.maildir, hash['userdb_mail'])
    assert_equal("*:bytes=1000000", hash["userdb_quota_rule"])
    assert_equal(mailbox.password, hash["password"])
  end

  def test_userdb_lookup
    mailbox = @domain.create_mailbox("aarvo")
    mailbox.quota = "1M"

    results = do_test_script(["L /userdb/#{mailbox.username}"])

    assert_equal("O", results.first[0])

    hash = {}

    assert_nothing_raised do
      hash = JSON.load(results.first[1..-1])
    end

    assert_equal(mailbox.username, hash['user'])
    assert_equal(mailbox.directory, hash["home"])
    assert_equal(mailbox.uid, hash["uid"])
    assert_equal(mailbox.gid, hash["gid"])
    assert_equal("maildir:"+mailbox.maildir, hash['mail'])
    assert_equal("*:bytes=1000000", hash["quota_rule"])
  end

  def test_nonexistent_user
    results = do_test_script(["L /passdb/idonotexist@foo.com"])
    assert_equal("N", results.first[0])
  end
  
  def test_shell_user
    test_user = fetch_test_user
    do_skip "No test user" if test_user.nil?

    hostname = Symbiosis::Host.fqdn
    #
    # Create the domain
    #
    domain = Symbiosis::Domain.new(hostname, @prefix)
    domain.create

    mailbox = Symbiosis::Domains.find_mailbox(test_user.name + "@" + hostname, @prefix)
    mailbox.password = "abc"

    # do the test twice, with and without the hostname
    [mailbox.username, test_user.name].each do |username|
      results = do_test_script(["L /passdb/#{username}"])

      assert_equal("O", results.first[0], "Failed to login with username #{username.inspect}")

      hash = {}

      assert_nothing_raised do
        hash = JSON.load(results.first[1..-1])
      end

      assert_equal(mailbox.username, hash['userdb_user'])
      assert_equal(mailbox.directory, hash["userdb_home"])
      assert_equal(mailbox.uid, hash["userdb_uid"])
      assert_equal(mailbox.gid, hash["userdb_gid"])
      assert_equal("maildir:"+mailbox.maildir, hash['userdb_mail'])
      assert_equal(mailbox.password, hash["password"])
    end
  end
end
