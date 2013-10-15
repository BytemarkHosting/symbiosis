$: << "../.."

exit 0 if Process.euid != 0

require 'test/unit'
require "tempfile"
require 'yaml'
require 'timeout'
require 'fileutils'

# TODO Rewrite the basics of these tests..

class Exim4ConfigTest < Test::Unit::TestCase

  # This tests the actual Exim4 routing.
  #
  #

  EXIM_BINARY="/usr/sbin/exim4"

  LOCAL_PART_REGEXP       = "[^\.@%!\/\|\s][^@%!\/\|\s]*"
  DOMAIN_REGEXP           = "[A-Za-z0-9\.-]+"
  EMAIL_ADDRESS_REGEXP    = "#{LOCAL_PART_REGEXP}@#{DOMAIN_REGEXP}"

  def setup
    # Create a temporary directory for all our stuff.
    @tempdir = nil
    loop do
      @tempdir = File.join("/tmp", File.basename($0)+"."+$$.to_s+"."+Time.now.usec.to_s)
      FileUtils.mkdir(@tempdir) unless File.exists?(@tempdir)
      if File.exists?(@tempdir)
        puts "Created directory #{@tempdir}" if $DEBUG
        break
      end
    end
    @tempdir = File.expand_path(@tempdir)
    @tempdir.freeze

    # Now we've got a temporary directory set up we can set up our exim
    # directory.

    FileUtils.mkdir_p(File.join(@tempdir, "exim4", "blacklist"))
    FileUtils.mkdir_p(File.join(@tempdir, "exim4", "whitelist"))

    # We need to set this up so we can test spam/av scanning
    FileUtils.mkdir_p(File.join(@tempdir, "spool", "scan"))
    FileUtils.mkdir_p(File.join(@tempdir, "spool", "input"))
    FileUtils.chown_R("Debian-exim", "Debian-exim", File.join(@tempdir, "spool"))

    # Copy all the config snippets over
    FileUtils.cp_r(File.join("../..", "exim4","symbiosis.d"),File.join(@tempdir,"exim4"))
    FileUtils.cp_r(File.join("../..", "exim4","Makefile"),File.join(@tempdir,"exim4"))

    # We need to know where the test exim4.conf is so we can pass it to exim4
    # when testing
    @exim4_conf = File.join(@tempdir, "exim4", "exim4.conf")

    # Read in our current exim4.conf so we can modify it
    macro_snippet_fn = File.join(@tempdir, "exim4", "symbiosis.d", "00-main", "10-base-macros")
    macro_snippet = File.open(macro_snippet_fn,"r"){|fh| fh.read}

    # Change where exim thinks /etc is
    macro_snippet.gsub!(/^ETC_DIR\s*=\s*.*$/, "ETC_DIR = #{@tempdir}")

    # Change where exim thinks the /srv directory is
    macro_snippet.sub!(/^VHOST_DIR\s*=\s*(.+)$/, 'VHOST_DIR = '+@tempdir+'\1')
    @vhost_dir = File.join(@tempdir, $1)

    # work out where the config directory should be
    macro_snippet =~ /^VHOST_CONFIG_DIR\s*=\s*(.*)$/
    @vhost_config_dir = $1

    # and where the mailbox directory should be
    macro_snippet =~ /^VHOST_MAILBOX_DIR\s*=\s*(.*)$/
    @vhost_mailbox_dir = $1


    # And write
    File.open(macro_snippet_fn, "w+"){|fh| fh.puts(macro_snippet)}
    
    # Add in the spool directory 
    File.open(File.join(@tempdir, "exim4",  "symbiosis.d", "00-main", "11-spool-directory"), "w") do |fh|
      fh.puts("spool_directory = "+File.join(@tempdir, "spool"))
    end

    print `cd #{File.join(@tempdir,"exim4")} && make`
  end

  def teardown
    FileUtils.rm_rf(@tempdir) if @tempdir =~/^\/tmp/ and !$DEBUG
  end

  def do_acl_setup
    # This file contains the settings we're using in the ACL tests, such as
    # domains.
    @acl_config = YAML.load_file("exim4_acl_tests/settings.yaml")

    # Create srv directories for each of the local domains
    @acl_config['local_domains'].each{ |d| FileUtils.mkdir_p(File.join(@vhost_dir, d, @vhost_config_dir)) }

    # write the passwd file
    @acl_config['passwd_entries'] = []
    @acl_config['local_users'].each do |u|
      u['username'] =~ /(#{LOCAL_PART_REGEXP})@(#{DOMAIN_REGEXP})/
      lp, domain = [$1, $2]
      mailbox = File.join(@vhost_dir, domain, @vhost_mailbox_dir, lp)
      FileUtils.mkdir_p(mailbox)
      File.open(File.join(mailbox, "password"),"w+"){|fh| fh.puts u['password']}
    end

    # Write out allowed relay IPs
    File.open(File.join(@tempdir, "exim4", "relay_from_hosts"),"w"){|fh| fh.puts @acl_config['relay_from_hosts'].join("\n")}

    # Sort out white and blacklists
    %w(blacklist whitelist).each do |list|
      %w(by_ip by_sender by_hostname).each do |by|
        next unless @acl_config.has_key?(list) and @acl_config[list].has_key?(by)
        File.open(File.join(@tempdir, "exim4", list, by), 'w+'){|fh| fh.puts @acl_config[list][by].join("\n")}
      end
    end
  end

  def do_exim4_bt(address, destination, router = nil, transport = nil)
    # We're looking for output like
    #
    # R: bytemark_user_aliases for patrick@bytemark.co.uk
    # R: bytemark_user_aliases for patch@bytemail.bytemark.co.uk
    # R: bytemark_passwd for patch@bytemail.bytemark.co.uk
    # R: system_aliases for patch@bytemail.bytemark.co.uk
    # R: userforward for patch@bytemail.bytemark.co.uk
    # R: procmail for patch@bytemail.bytemark.co.uk
    # R: maildrop for patch@bytemail.bytemark.co.uk
    # R: local_user for patch@bytemail.bytemark.co.uk
    # patch@bytemail.bytemark.co.uk -> /home/patch/Maildir/
    #   transport = maildir_home

    # R: dnslookup_relay_to_domains for patrick@gmail.com
    # patrick@gmail.com
    #   router = dnslookup_relay_to_domains, transport = remote_smtp
    #   host gmail-smtp-in.l.google.com      [216.239.59.27]  MX=5
    #   host alt1.gmail-smtp-in.l.google.com [72.14.215.27]   MX=10
    #   host alt1.gmail-smtp-in.l.google.com [72.14.215.114]  MX=10
    #   host alt2.gmail-smtp-in.l.google.com [64.233.185.27]  MX=10
    #   host alt2.gmail-smtp-in.l.google.com [64.233.185.114] MX=10
    #   host gsmtp147.google.com             [209.185.147.27] MX=50
    #   host gsmtp183.google.com             [64.233.183.27]  MX=50

    # patch@lumi.talvi.net
    #     <-- patch@dominoid.net
    #   router = dspam_accept, transport = dspam_scan


    # So we need to match the line beginning with the address, and parse the following lines.
    #
    this_destination = this_router = this_transport = nil
    status = 0
    case transport
      when ":defer:"
        status = 1
      when ":fail:"
        status = 2
      when nil
        status = nil
    end

    test_destination = (not destination.nil?)
    test_transport = (not transport.nil?)
    test_router = (not router.nil?)

    op = `#{EXIM_BINARY} -C #{@exim4_conf} -bt #{address} 2>&1`
    assert_equal(status,$?.exitstatus, op) unless status.nil?
    puts op if $DEBUG

    op.split("\n").each do |line|
      case line
        when /^R:\s*([^\s]+) for (#{EMAIL_ADDRESS_REGEXP})$/ then
          this_router = $1
          this_destination = $2
        when /^#{EMAIL_ADDRESS_REGEXP}\s+->\s+(.*)$/ then
          this_destination = $1 #f this_destination.nil?
        when /^(#{EMAIL_ADDRESS_REGEXP})\s*$/ then
          this_destination = $1 #f this_destination.nil?
        when /^\s+<--\s+(#{EMAIL_ADDRESS_REGEXP})\s*$/ then
          # do nothing
        when /^\s+(router = ([^,]+), )?transport = ([^\s]+)\s*$/ then
          this_router = $2 unless $2.nil?
          this_transport = $3 #f this_transport.nil?
        when /^mail to ([^\s]+) is discarded$/ then 
          this_destination = ":blackhole:"
          this_transport = ":blackhole:"
        when /^([^\s]+) cannot be resolved at this time:/ then
          this_transport = ":defer:"
        when /^([^\s]+) is undeliverable:/ then
          this_transport = ":fail:"
      end
    end

    if test_destination
      assert_not_nil(this_destination, "No destination found in:\n"+op)
      assert_equal(destination, this_destination, "Incorrect destination found in:\n"+op)
    end

    if test_transport
      assert_not_nil(this_transport, "No transport found in:\n"+op)
      assert_equal(transport, this_transport, "Incorrect transport found in:\n"+op)
    end

    if test_router
      assert_not_nil(this_router, "No router found in:\n"+op)
      assert_equal(router, this_router, "Incorrect router found in:\n"+op)
    end
  end

  def do_exim4_bh(from_ip, to_ip, script)
    # This is to simulate an smtp session
    #
    from_ip   += ".#{rand(2**15-2**10)+2**10}" if from_ip.split(".").length == 4
    to_ip     += ".25" if to_ip.split(".").length == 4

    cmd = "#{EXIM_BINARY} -C #{@exim4_conf} -oMa #{from_ip} -oMi #{to_ip} -bh  #{from_ip}"
    cmd += ($DEBUG ? "" : " 2>/dev/null")
    puts cmd if $DEBUG
    IO.popen(cmd, 'w+') do |exim|
      line, code = do_smtp_readline(exim)
      assert_equal(220, code, "Exim returned #{line}")

      script.each do |input_line, expected_code|
        puts input_line if $DEBUG
        exim.puts(input_line)
        line, code = do_smtp_readline(exim)
        assert_equal(expected_code, code, "Exim returned #{line} after #{input_line}\n")
      end
    end
  end

  def do_acl_script(filename)
    #
    # This is the exim4 pipe object.
    #
    exim = nil

    # This is to simulate an smtp session
    File.open(filename) do |script|
      data_to_send = ""
      while not script.eof? do
        line = script.gets.chomp
        next if line =~ /^#/
        if exim.nil?
          to_ip = @acl_config['local_ip']+".25"
          from_ip = line+".#{rand(2**15-2**10)+2**10}" if line.split(".").length == 4
          cmd = "#{EXIM_BINARY} -C #{@exim4_conf} -oMa #{from_ip} -oMi #{to_ip} -bh #{from_ip} 2>&1"
          puts cmd if $DEBUG
          exim = IO.popen(cmd, 'w+')
        elsif line =~ /^(\d\d\d) ?(.*)?/
          code, msg = [Integer($1), $2]
          # Send the data if we've got any
          exim.puts(data_to_send) unless data_to_send.empty?
          # Now see what exim says
          r_msg, r_code = do_smtp_readline(exim)
          assert_equal(code, r_code, "ACL test failed after line #{script.lineno} of #{filename} (#{r_msg})")
          assert_equal(msg,  r_msg,  "ACL test failed after line #{script.lineno} of #{filename}") unless msg.empty?
          data_to_send = ""
        else
          data_to_send << line+"\n"
        end
      end
    end

  ensure
    #
    # Make sure the exim4 pipe is closed at the end of each ACL test.
    #
    exim.close if exim.is_a?(IO) and not exim.closed?
  end

  def do_smtp_readline(pipe)
    all_lines = []
    line = ""
    msg = ""
    code = -1
    begin
      Timeout.timeout(20) do
        while line !~ /^(\d+) (.*)/ do
          line = pipe.readline
          all_lines << line
          puts line if $DEBUG
        end
      end
      code, msg = [Integer($1), $2.chomp]
    rescue Timeout::Error
      puts all_lines.join
      warn "Caught timeout!"
      pipe.close
    rescue EOFError
      puts all_lines.join("\n")
      warn "EOF!"
    end
    [msg, code]
  end

  # Things to check
  #
  # a) General config issues
  # b) Access Control Lists
  # c) Routers
  # d) Transports
  # e) Rewriting
  # f) Authentication

  ################################################################################
  # ACLs
  ################################################################################

  def test_acl_blacklists
    # setup the acl
    do_acl_setup()

    %w(normal_ip blacklisted_ip whitelisted_ip).each do |test|
      do_acl_script('exim4_acl_tests/'+test)
    end
  end

  def is_running?(pidfile)
    # make sure the pidfile exists
    return false unless File.exists?(pidfile)

    pid = File.open(pidfile){|fh| fh.gets}.chomp
    # Check the pid
    return false unless File.exists?("/proc/#{pid}")

    # OK everything is working
    return true
  end

  def test_acl_check_spam

    # Only run these tests if SA is running
    if !is_running?('/var/run/spamd.pid')
      puts "Spamassassin not running"
      return
    end

    # setup the acl
    do_acl_setup()

    config_dir = File.join(@vhost_dir, @acl_config['local_domains'].first, @vhost_config_dir)
    # If no antispam file is there we should accept
    do_acl_script('exim4_acl_tests/antispam_accept')

    # If one is there, we should reject
    FileUtils.touch(File.join(config_dir, "antispam"))
    do_acl_script('exim4_acl_tests/antispam_reject')

    # If the files is there, and starts with the word "tag" then accept the
    # mail (but tag it, although we can't test for that here)
    File.open(File.join(config_dir, "antispam"),"w+"){|fh| fh.puts("tag my mail")}
    do_acl_script('exim4_acl_tests/antispam_accept')

    # If the file is there and begins with anything other than "tag", then
    # reject the mail.
    File.open(File.join(config_dir, "antispam"),"w+"){|fh| fh.puts("please do not tag my mail")}
    do_acl_script('exim4_acl_tests/antispam_reject')

    # Test to make sure that when the file is unreadable, we default to reject
    FileUtils.chmod(0000,File.join(config_dir, "antispam"))
    do_acl_script('exim4_acl_tests/antispam_reject')
  end

  def test_acl_check_antivirus
    # Only run these tests if clam is running
    if !is_running?('/var/run/clamav/clamd.pid')
      puts "Clamav not running"
      return
    end

    # setup the acl
    do_acl_setup()

    config_dir = File.join(@vhost_dir, @acl_config['local_domains'].first, @vhost_config_dir)
    # Now do the same checks with anti-virus
    #
    # No anti-virus file? Then accept.
    do_acl_script('exim4_acl_tests/antivirus_accept')

    # OK the file is there now, so reject (as per default)
    FileUtils.touch(File.join(config_dir, "antivirus"))
    do_acl_script('exim4_acl_tests/antivirus_reject')

    # OK, now the file contains "tag" so accept, and tag
    File.open(File.join(config_dir, "antivirus"),"w+"){|fh| fh.puts("tag my mail")}
    do_acl_script('exim4_acl_tests/antivirus_accept')

    # But now it has something other than tag, so reject!
    File.open(File.join(config_dir, "antivirus"),"w+"){|fh| fh.puts("please do not tag my mail")}
    do_acl_script('exim4_acl_tests/antivirus_reject')

    # Test to make sure that when the file is unreadable, we default to reject
    FileUtils.chmod(0000,File.join(config_dir, "antivirus"))
    do_acl_script('exim4_acl_tests/antivirus_reject')
  end

  def test_acl_check_port_587
    do_acl_setup
    # Test we can relay on port 587 from localhost
    # Test we can relay on port 587 from an allowed domain 
    # Test we cannot relay on port 587 from a random IP, without authentication

    username = @acl_config['local_users'].first['username']
    password = @acl_config['local_users'].first['password']

    script = [
      ["EHLO test.test",  250],
      ["MAIL FROM:<#{username}>", 250],
      ["RCPT TO:<#{username}>", 250]
    ]
    do_exim4_bh("127.0.0.1", "127.0.0.1.587", script)
    relay_ip = @acl_config['relay_from_hosts'].first
    do_exim4_bh(relay_ip, @acl_config['local_ip']+".587", script)
    
    script[-1][-1] = 550
    do_exim4_bh(@acl_config['remote_ip'], @acl_config['local_ip']+".587", script)
  end

  ################################################################################
  # ROUTERS
  ################################################################################

  def test_router_dnslookup
    do_exim4_bt("test@example.com", "test@example.com", "dnslookup", "remote_smtp")
  end

#  def test_router_vhost_rewrites
#    do_acl_setup
#    @acl_config['rewrite_domains'].each { |from, to| FileUtils.ln_s(File.join(@vhost_dir, to), File.join(@vhost_dir, from)) }
#
#    do_write_exim4_rewrites(@exim4_conf)
#    @acl_config['rewrite_domains'].each {|from, to| do_exim4_bt("user@"+from, "user@"+to) }
#  end

  def test_router_vhost_no_local_mail
    do_acl_setup
    domain = @acl_config['local_domains'].last
    do_exim4_bt("test@"+domain, "test@"+domain, "vhost_no_local_mail", "remote_smtp")
  end

  def test_router_vhost_forward
    do_acl_setup
    domain = @acl_config['local_domains'].first

    # We can't test for :unknown:
    [
      [ "alias_test1", "test1@remote.domain", nil, nil ],
      [ "alias_test2", "|/a-really-secure-programme", "vhost_forward", "address_pipe" ],
      [ "alias_test3", "/straight/to/a/file", "vhost_forward", "address_file" ],
      [ "alias_test4", "/straight/to/a/directory/", "vhost_forward", "address_directory" ],
      [ "alias_test5", ":blackhole:", "vhost_forward", ":blackhole:" ],
      [ "alias_test6", ":fail:", "vhost_forward", ":fail:" ],
      [ "alias_test7", ":defer:", "vhost_forward", ":defer:" ],
    ].each do |lp, action, router, transport|
      mailbox = File.join(@vhost_dir, domain, @vhost_mailbox_dir, lp)
      FileUtils.mkdir_p(mailbox)
      File.open(File.join(mailbox,"forward"),"w+"){|fh| fh.puts action}
      # change the action for testing
      action = lp+"@"+domain if action == ":fail:" or action == ":defer:" or action == ":unknown:"
      do_exim4_bt(lp+"@"+domain, action, router, transport)
    end
  end

  def test_router_vhost_forward_sieve
    do_acl_setup
    domain = @acl_config['local_domains'].first
    lp = "sieve_test"
    mailbox = File.join(@vhost_dir, domain, @vhost_mailbox_dir, lp)
    FileUtils.mkdir_p(mailbox)
    FileUtils.touch(File.join(mailbox,"sieve"))
    action = lp+"@"+domain
    router = "vhost_forward_sieve"
    transport = "dovecot_lda"
    # change the action for testing
    do_exim4_bt(lp+"@"+domain, action, router, transport)
  end

  def test_router_vhost_vacation
    do_acl_setup
    domain = @acl_config['local_domains'].first
    lp = "vacation_test"
    mailbox = File.join(@vhost_dir, domain, @vhost_mailbox_dir, lp)
    FileUtils.mkdir_p(mailbox)
    File.open(File.join(mailbox,"vacation"),"w+"){|fh| fh.puts "I'm away until forever"}
    do_exim4_bt(lp+"@"+domain, lp+"@"+domain, "vhost_vacation", "vhost_vacation")
    # TODO This needs to be tested to make sure it doesn't reply to junk.
  end

  def test_router_vhost_mailbox
    do_acl_setup()
    @acl_config['local_users'].each do |u|
      u['username'] =~ /(#{LOCAL_PART_REGEXP})@(#{DOMAIN_REGEXP})/
      local_part, domain = [$1, $2]
      do_exim4_bt(u['username'],File.join(@vhost_dir,domain,@vhost_mailbox_dir,local_part,"Maildir/"), "vhost_mailbox", "address_directory")
    end
  end

  def test_router_vhost_aliases
    do_acl_setup()
    domain = @acl_config['local_domains'].first

    alias_fn = File.join(@vhost_dir, domain, "config", "aliases")
    aliases = [
      [ "alias_test1", "test1@remote.domain", nil, nil ],
      [ "alias_test2", "|/a-really-secure-programme", "vhost_aliases", "address_pipe" ],
      [ "alias_test3", "/straight/to/a/file", "vhost_aliases", "address_file" ],
      [ "alias_test4", "/straight/to/a/directory/", "vhost_aliases", "address_directory" ],
      [ "alias_test5", ":blackhole:", "vhost_aliases", ":blackhole:" ],
      [ "alias_test6", ":fail:", "vhost_aliases", ":fail:" ],
      [ "alias_test7", ":defer:", "vhost_aliases", ":defer:" ],
    ]
    File.open(alias_fn,"w+"){|fh| aliases.each{|a| fh.puts a.first(2).join(": ")}}

    aliases.each do |lp, action, router, transport|
      # change the action for testing
      action = lp+"@"+domain if action == ":fail:" or action == ":defer:" or action == ":unknown:"
      do_exim4_bt(lp+"@"+domain, action, router, transport)
    end
  end

  def test_router_vhost_aliases_check
    do_acl_setup()
    domain = "local.domain"
    alias_fn = File.join(@vhost_dir, domain, "config", "aliases")
    aliased_lp = "alias_check1"
    actual_lp = "real_test1"
    mailbox = File.join(@vhost_dir, domain, @vhost_mailbox_dir, actual_lp)
    FileUtils.mkdir_p(mailbox)
    # Write the aliases file
    File.open(File.join(@vhost_dir,domain,"config/aliases"),"w+"){|fh| fh.puts("#{aliased_lp}: #{actual_lp}")}

    FileUtils.chown_R("1000","1000", File.join(@vhost_dir,domain))

    do_acl_script('exim4_acl_tests/router_vhost_aliases_check')
  end

  def test_router_vhost_default_forward
    do_acl_setup()
    @acl_config['local_users'].first['username'] =~ /(#{LOCAL_PART_REGEXP})@(#{DOMAIN_REGEXP})/
    local_part, domain = [$1, $2]

    # Make sure we can't route this already.
    do_exim4_bt("nobody@"+domain,"nobody@"+domain , nil, ":fail:")

    config_dir = File.join(@vhost_dir, domain, @vhost_config_dir)
    FileUtils.mkdir_p(config_dir)
    File.open(File.join(config_dir, 'default_forward'), "w+"){|fh| fh.puts "/tmp/default_forward/"}

    # Now make sure we can...
    do_exim4_bt("nobody@"+domain,"/tmp/default_forward/", "vhost_default_forward", "address_directory")
  end

  def test_router_vhost_default_forward_check
  end

  #
  # postmaster should get re-written to root@$(hostname), which (in this
  # instance) gets delivered by the exim4 mail_for_root router.
  #
  def test_router_vhost_postmaster
    do_acl_setup()
    domain = @acl_config['local_domains'].first
    do_exim4_bt("postmaster@"+domain, "/var/mail/mail", "mail_for_root", "address_file")
  end

  def test_router_system_aliases
    do_acl_setup()

    if File.exists?('/etc/hostname')
      this_hostname = File.read('/etc/hostname').chomp
    else
      this_hostname = "localhost"
    end

    File.open(File.join(@tempdir, "aliases"),'w+'){|fh| fh.puts("nobody: root")}
    # This should route just fine
    do_exim4_bt("nobody@"+this_hostname, "/var/mail/mail", "mail_for_root", "address_file")

    # This shouldn't route just fine as no alias for root at this domain has been defined
    #
    local_domain = @acl_config['local_domains'].first
    do_exim4_bt("nobody@"+local_domain,"nobody@"+local_domain , nil, ":fail:")

  end

  def test_router_mail_for_local_root
    do_acl_setup

    if File.exists?('/etc/hostname')
      this_hostname = File.read('/etc/hostname').chomp
    else
      this_hostname = "localhost"
    end
    # This should route just fine
    do_exim4_bt("root@"+this_hostname, "/var/mail/mail", "mail_for_root", "address_file")

    # This shouldn't route as no alias for root at this domain has been defined
    #
    local_domain = @acl_config['local_domains'].first
    do_exim4_bt("root@"+local_domain, "root@"+local_domain, nil, ":fail:")
  end

  def test_postmaster_for_any_domains
    do_acl_setup

    if File.exists?('/etc/hostname')
      this_hostname = File.read('/etc/hostname').chomp
    else
      this_hostname = "localhost"
    end

    # This should route just fine
    do_exim4_bt("postmaster@"+this_hostname, "/var/mail/mail", "mail_for_root", "address_file")


    local_domain = @acl_config['local_domains'].first
    # This should route just fine even though no alias for postmaster at this
    # domain has been defined (going through to root)
    #
    do_exim4_bt("postmaster@"+local_domain, "/var/mail/mail", "mail_for_root", "address_file")

    # Now check that when we actually have an alias, it doesn't go through to root as before
    mailbox = File.join(@vhost_dir, local_domain, @vhost_mailbox_dir, "postmaster")
    FileUtils.mkdir_p(mailbox)
    File.open(File.join(mailbox,"forward"), 'w+'){|fh| fh.puts "/var/mail/postmaster"}

    do_exim4_bt("postmaster@"+local_domain, "/var/mail/postmaster", "vhost_forward", "address_file")
  end

  ################################################################################
  # TRANSPORTS
  ################################################################################

  #
  # I don't think there is anything we can do with this.  We'll just have to
  # trust exim.
  #

  ################################################################################
  # REWRITES
  ################################################################################

  def test_localhost_rewrite
    do_acl_setup

    if File.exists?('/etc/hostname')
      this_hostname = File.read('/etc/hostname').chomp
    end

    if this_hostname == "localhost"
      puts "Cannot do localhost rewrite tests, since this host thinks it is called localhost."
      return 
    end

    lp = "rewrite_test"
    mailbox = File.join(@vhost_dir, this_hostname, @vhost_mailbox_dir, lp)
    FileUtils.mkdir_p(mailbox)
    do_exim4_bt(lp+"@localhost", mailbox+"/Maildir/", "vhost_mailbox", "address_directory")
  end

  ################################################################################
  # AUTHENTICATION
  ################################################################################

  # This is now done externally.

end
