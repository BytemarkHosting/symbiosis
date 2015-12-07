require 'test/unit'
require 'symbiosis/utils'
require 'tmpdir'
require 'tempfile'
require 'etc'

class TestUtils < Test::Unit::TestCase

  include Symbiosis::Utils

  def setup
    #
    # The prefix has to be in a directory admin can read..
    #
    @prefix = Dir.mktmpdir("srv","/tmp")
    @prefix.freeze
  end

  def teardown
    if Process.uid == 0
      Process.euid = 0
      Process.egid = 0
    end

    FileUtils.remove_entry_secure(@prefix) if File.directory?(@prefix)
  end

  def test_mkdir_p
    dir = File.join(@prefix,"a","b")
    uid = Process.euid
    gid = Process.groups.first
    gid = Process.egid if gid.nil?

    assert_nothing_raised{ mkdir_p(dir, :uid => uid, :gid => gid, :mode => 0700) }
    assert(File.directory?(dir),"mkdir_p did not create the directroy #{dir}")

    #
    # Now stat the directory.
    #
    stat = File.stat(dir)
    assert_equal(uid, stat.uid, "mkdir_p did not set the uid correctly")
    assert_equal(gid, stat.gid, "mkdir_p did not set the gid correctly")
    assert_equal(0700, stat.mode & 0700, "Permissions on #{dir} are not what were set.")

    #
    # Make sure we can't create a directory on top of a file
    #
    file = File.join(dir,"c")
    FileUtils.touch(file)
    assert(File.file?(file), "#{file} is not a file when it should be")

    assert_raise(Errno::EEXIST) { mkdir_p(file) }

    #
    # Make sure we can't create a directory under a file.
    #
    filedir = File.join(file,"d")
    assert(!File.exist?(filedir),"#{filedir} exists when it hasn't been created yet.")

    assert_raise(Errno::ENOTDIR) { mkdir_p(filedir) }


    #
    # Make sure we can't overwrite a symlink
    #
    syml = File.expand_path(File.join(dir,"..","bb"))
    File.symlink(dir, syml)
    assert(File.symlink?(syml),"#{syml} is not a symlink when it should be")

    assert_raise(Errno::EEXIST) { mkdir_p(syml) }

    #
    # Make sure we can create a directory the other side of a symlink
    #
    symldir = File.join(syml,"cc")

    assert_nothing_raised { mkdir_p(symldir) }

    assert(File.directory?(File.join(dir,"cc")))

  end

  def test_random_string
    #
    # Should return a string, missing some confusing letters.
    #
    sz  = 1000
    str = random_string(sz)

    assert_equal(sz,str.length,"The random string was the wrong size")
    assert_match(/^[a-hjkmnp-zA-HJ-NP-Z2-9]+$/,str)
  end

  def test_get_param
    param = "test-get-param"
    fn = File.join(@prefix, param)

    assert(!File.exist?(fn))
    assert_equal(nil,get_param(param, @prefix))

    FileUtils.touch(fn)
    assert_equal(true,get_param(param, @prefix))

    %w(true True TRUE yes).each do |value|
      File.open(fn,"w"){|fh| fh.write value }
      assert_equal(true,get_param(param, @prefix))
    end

    %w(false False FaLsE no).each do |value|
      File.open(fn,"w"){|fh| fh.write value }
      assert_equal(false,get_param(param, @prefix))
    end

    value = "this value"
    File.open(fn,"w"){|fh| fh.write value }
    assert_equal(value, get_param(param, @prefix))

    value = "this value\nthat_value\n"
    File.open(fn,"w"){|fh| fh.write value }
    assert_equal(value, get_param(param, @prefix))
  end

  def test_get_param_with_dir_stack
    dirs = %w(a b c).map{|d| File.join(@prefix, d)}
    param = "test"

    #
    # Create each value in reverse order.  We should get the most recently
    # created variable back.
    #
    dirs.reverse.each do |dir|
      Dir.mkdir(dir)
      value = File.basename(dir)

      File.open(File.join(dir, param), "w") do |fh|
        fh.print(value)
      end

      assert_equal(value, get_param_with_dir_stack(param, dirs))
    end

    #
    # Now set the "top" value to false.  This should return false.
    #
    value = "false"
    dir = dirs.first
    File.open(File.join(dir, param), "w") do |fh|
      fh.print(value)
    end
    assert_equal(false, get_param_with_dir_stack(param, dirs))

    #
    # Now remove the file.  This should now fall through to the second value.
    #
    File.unlink(File.join(dir, param))
    value = File.basename(dirs[1])
    assert_equal(value, get_param_with_dir_stack(param, dirs))
  end

  def test_set_param
    #
    # If we're running as root, make sure the directory is owned by a
    # non-system user.
    #
    if 0 == Process.uid
      File.chown(1000,1000,@prefix)
      Process.egid = 1000
      Process.euid = 1000
    end

    param = "test-set-param"
    fn = File.join(@prefix, param)

    value = false
    assert_nothing_raised do
      assert_equal(value, set_param(param, value, @prefix))
    end
    assert(!File.exist?(fn))

    value = nil
    assert_nothing_raised do
      assert_equal(value, set_param(param, value, @prefix))
    end
    assert(!File.exist?(fn))

    value = true
    assert_nothing_raised do
      assert_equal(value, set_param(param, value, @prefix))
    end
    assert(File.zero?(fn))

    value = "test-val"
    assert_nothing_raised do
      assert_equal(value, set_param(param, value, @prefix))
    end
    assert_equal(value, File.read(fn))

    value = "test-val\nother-val\n"
    assert_nothing_raised do
      assert_equal(value, set_param(param, value, @prefix))
    end
    assert_equal(value, File.read(fn))

    value = false
    assert_nothing_raised do
      assert_equal(value, set_param(param, value, @prefix))
    end
    assert(!File.exist?(fn))

  ensure
    #
    # Make sure we return to root.
    #
    if 0 == Process.uid
      Process.euid = 0
      Process.egid = 0
    end
  end

  def test_safe_open_as_root
    unless 0 == Process.uid
      warn "\nSkipping test_safe_open_as_root as not running as root"
      return
    end

    if ENV.has_key?("FAKEROOTKEY")
      warn "\nSkipping test_safe_open_as_root as it is running under fakeroot"
      return
    end

    #
    # Set up a typical evil scenario
    #
    fn  = File.join(@prefix, "actual-file")
    sym = File.join(@prefix, "symlinked-file")

    #
    # This is our precious file, owned by root.
    #
    Process.euid = 0
    FileUtils.touch(fn)

    #
    # Make sure the directory is owned by our malicious user.
    #
    File.chown(1000,1000,@prefix)

    #
    # Evil user symlinks back to our precious file, wanting us to overwrite it
    #
    Process.euid = 1000
    File.symlink(fn, sym)

    #
    # Back to root again.
    #
    Process.euid = 0

    #
    # Check we've got things right
    #
    assert_equal(1000, File.lstat(sym).uid, "The malicious symlink is not owned by UID 1000")
    assert_equal(0,     File.stat(sym).uid, "The precious file is not owned by root!")

    #
    # Try and overwrite the file, via the evil symlink.
    #
    assert_raise(Errno::EPERM) do
      #
      # DENIED!
      #
      safe_open(sym,"a+") {|fh| fh.puts "test" }
    end

    #
    # Now try and open the file all by itself.
    #
    assert_nothing_raised do
      #
      # ALLOWED!
      #
      safe_open(fn,"a+") {|fh| fh.puts "test" }
    end

    #
    # Now try a few modes that should truncate the file
    #
    ["w", "w+", File::RDWR|File::TRUNC].each do |mode|
      assert_raise(Errno::EPERM) do
        safe_open(fn,mode) {|fh| fh.puts "test" }
      end
    end
  end

  def test_safe_open_functionality
    fn = File.join(@prefix,"safe-open-functionality")

    safe_open(fn,"a+") {|fh| fh.puts fn }

    #
    # This file should be owned by Process.euid, Process.egid, and with a mask of 0666 - umask
    #
    stat = File.stat(fn)
    assert_equal(Process.euid, stat.uid)
    assert_equal(Process.egid, stat.uid)
    assert_equal(0666 - File.umask, stat.mode - 0100000)

    #
    # Remove the file, and set some options
    #
    File.unlink(fn)

    opts = {:mode => 0600}
    opts = {:uid => 1000, :gid => 2000}.merge(opts) if Process.euid == 0

    safe_open(fn, "a+", opts) {|fh| fh.puts fn }
    #
    # and check
    #
    stat = File.stat(fn)
    if Process.euid == 0
      assert_equal(1000, stat.uid)
      assert_equal(2000, stat.gid)
    end
    assert_equal(0600, stat.mode - 0100000)
  end

  def test_parse_quota
    # TODO
  end

  def test_lock
    fn = File.join(@prefix,"lock")

    fh_parent = File.open(fn, "w+")
    assert_equal(0, lock(fh_parent))

    #
    # Make sure the file exists.
    #
    assert(File.exist?(fn),"Lock file #{fn} doesn't exist.")

    #
    # Check to see if we can check the lock again..
    #
    pid = fork do
      File.open(fn, "r") do |fh_child|
        assert_raise(Errno::ENOLCK) {  lock(fh_child) }
      end
    end

    Process.wait(pid)

    unlock(fh_parent)

    pid = fork do
      File.open(fn, "r") do |fh_child|
        assert_nothing_raised {  lock(fh_child) }
      end
    end

    Process.wait(pid)

  end


end

