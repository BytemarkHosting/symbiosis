#
#
require 'socket'
require 'test/unit'
require 'tmpdir'
require 'tempfile'
require 'symbiosis/domains'

class TestApacheLogger < Test::Unit::TestCase

  def setup
    @prefix = Dir.mktmpdir("srv")
    File.chown(1000,1000,@prefix) if Process.uid < 1000

    @nonprefix = Dir.mktmpdir("other")

    @default_log = Tempfile.new("tc_httpd_logger", @prefix)
    @default_filename = @default_log.path

    @domains = []

    #
    # Go builds stuff in obj-..
    #
    @binary = Dir.glob(File.expand_path(File.join(File.dirname(__FILE__),'..','obj-*', 'bin', 'symbiosis-httpd-logger'))).first
    if @binary.nil?
      @binary = '/usr/sbin/symbiosis-httpd-logger'
    end

    unless File.executable?(@binary)
      omit("Missing binary for symbiosis-httpd-logger")
    end

  end

  def teardown
    #
    #  Delete the temporary domain
    #
    @domains.each{|d| d.destroy() unless d.nil? }

    #
    # Close + remove our default logfile
    #
    @default_log.close if @default_log.is_a?(Tempfile)

    #
    # Remove the @prefix directory
    #
    FileUtils.remove_entry_secure @prefix
    FileUtils.remove_entry_secure @nonprefix
  end

  #
  # This tests the options we can set.
  #
  def test_setup
    flags = %w(-s -f 500 -u 100 -g 200 -l foo.log) + ["-p", @prefix, @default_filename]
    IO.popen([@binary] + flags, "r+") {|f| f.close_write; f.close_read}
    assert_equal(0, $?.exitstatus, "#{@binary} exited non-zero when testing flags")
  end

  def test_logging
    #
    #  Create the domain
    #
    10.times do |i|
     @domains << Symbiosis::Domain.new("existent-#{i}.com", @prefix)
    end
    @domains.each{|d| d.create }

    #
    # We'll delete this domain half-way
    #
    to_delete = Symbiosis::Domain.new("deleted.com", @prefix)
    to_delete.create
    @domains << to_delete

    #
    # Add a non-existent domain to the mis
    #
    non_existent = Symbiosis::Domain.new("non-existent.com", @prefix)
    @domains << non_existent

    test_lines = []
    test_lines2 = []

    10.times do |i|
      test_lines  += @domains.collect{|d| [d, "#{i} " + Symbiosis::Utils.random_string(40)] }
      test_lines2 += @domains.collect{|d| [d, "#{10+i} " + Symbiosis::Utils.random_string(40)] }
    end

    flags = %w(-s -f 4) + ["-p", @prefix, @default_filename]

    IO.popen([@binary]+flags, 'r+') do |pi|
      test_lines.each do |d, l|
        pi.puts "#{d.name} #{l}"
      end

      to_delete.destroy

      test_lines2.each do |d, l|
        pi.puts "#{d.name} #{l}"
      end
    end

    #
    # If we get this far, open the domain's access logs and look for foo and bar.  Mash the test lines into a hash.
    #
    log_line_hash = Hash.new{|h,k| h[k] = []}

    (test_lines + test_lines2).each do |d, l|
      #
      # We expect the last 10 lines of the deleted domain to appear, and all
      # the non-existent ones in the shared access log.
      #
      unless [non_existent, to_delete].include?(d)
        # next if to_delete == d and l =~ /^\d /
        log_line_hash[d] << l
      end
      log_line_hash[non_existent] << "#{d.name} #{l}"
    end

    log_line_hash.each do |d, lines|

      if File.directory?(d.directory)
        # Make sure the file exists
        access_log = File.join(d.log_dir, "access.log")
      else
        # When we write to the default log, the domain is still attached.
        access_log = @default_filename
      end

      assert(File.exist?(access_log), "Access log #{access_log} for #{d.name} not found")

      # And that we can read it.
      logged_lines = File.readlines(access_log).collect{|l| l.to_s.chomp}
      assert_equal(lines, logged_lines, "Mismatch in logs for domain #{d} in file #{access_log}")
    end

    assert(!File.directory?(non_existent.directory), "Non-existent domain's directory created.")
    assert(!File.directory?(to_delete.directory), "Non-existent domain's directory created.")

  end

  def test_symlinked_domain
    domain = Symbiosis::Domain.new("example.com", @prefix)
    domain.create
    @domains << domain

    FileUtils.ln_s(domain.directory, File.join(@prefix, "example.org"))
    FileUtils.ln_s(domain.name, File.join(@prefix, "example.net"))
    FileUtils.ln_s(@nonprefix, File.join(@prefix, "example.info"))
    FileUtils.ln_s('/var', File.join(@prefix, "example.biz"))

    test_lines = []
    10.times do |i|
      test_lines  += %w(com net org info biz).collect{|d| ["example.#{d}", "#{i} " + Symbiosis::Utils.random_string(40)] }
    end

    flags = %w(-s -f 4) + ["-p", @prefix, @default_filename]

    IO.popen([@binary]+flags, 'r+') do |pi|
      test_lines.each do |d, l|
        pi.puts "#{d} #{l}"
      end
      pi.close_write
    end

    assert(!File.exists?(File.join("/var", "public", "logs", "access.log")), "Log file outside /srv created.")
  end

end
