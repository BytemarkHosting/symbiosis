# encoding: UTF-8

require 'test/unit'
require 'tmpdir'
require 'symbiosis'
require 'symbiosis/domain_skeleton'
require './helpers.rb'

# tests for DomainSkeleton - ensure hooks work, ensure skeleton copies correctly
class TestDomainSkeleton < Test::Unit::TestCase
  def setup
    Process.egid = 1000 if Process.gid.zero?
    Process.euid = 1000 if Process.uid.zero?

    Symbiosis.etc = File.realpath Dir.mktmpdir('etc')
    Symbiosis.prefix = File.realpath Dir.mktmpdir('srv')

    @verbose = $VERBOSE || $DEBUG ? ' --verbose ' : ''

    testd = File.dirname(__FILE__)

    @script = File.expand_path(File.join(testd,"..","bin","symbiosis-skel"))
    @script = '/usr/sbin/symbiosis-skel' unless File.exist?(@script)
    @script += @verbose
    make_skeleton
  end

  def make_skeleton
    skelpath = Symbiosis.path_in_etc('symbiosis/skel')

    Symbiosis::Utils.mkdir_p File.join(skelpath, 'test', 'deep')

    Symbiosis::Utils.set_param 'test-param', 'this is a test', skelpath
    Symbiosis::Utils.set_param 'test-param', 'also a test', File.join(skelpath, 'test')
    Symbiosis::Utils.set_param 'test-param', 'deep test', File.join(skelpath, 'test', 'deep')

    @skel = Symbiosis::DomainSkeleton.new skelpath
  end

  def teardown
    unless $DEBUG
      FileUtils.rm_rf Symbiosis.etc if File.directory?(Symbiosis.etc)
      FileUtils.rm_rf Symbiosis.prefix if File.directory?(Symbiosis.prefix)
    end

    Process.euid = 0 if Process.uid.zero?
    Process.egid = 0 if Process.gid.zero?
  end

  def test_copy
    domain = Symbiosis::Domain.new(nil, Symbiosis.prefix)
    domain.create
    
    @skel.copy! domain

    assert_equal 'this is a test', domain.get_param('test-param')
    assert_equal 'also a test', domain.get_param('test/test-param')
    assert_equal 'deep test', domain.get_param('test/deep/test-param')
  end

  def test_hooks
    hooks_dir = Symbiosis.path_in_etc('symbiosis', 'skel-hooks.d')

    result = TestHelpers.make_test_hook hooks_dir

    domain = Symbiosis::Domain.new(nil, Symbiosis.prefix)
    domain.create

    success = Symbiosis::DomainSkeleton::Hooks.run! 'domains-populated', [domain.name]

    assert_equal true, success

    assert_equal "domains-populated\n", result.args
    assert_equal "#{domain.name}\n", result.output
  end

  def test_symbiosis_skel
    hooks_dir = Symbiosis.path_in_etc('symbiosis', 'skel-hooks.d')

    result = TestHelpers.make_test_hook hooks_dir

    domain = Symbiosis::Domain.new(nil, Symbiosis.prefix)
    domain.create

    pid = spawn("#{@script} --etc=#{Symbiosis.etc} --prefix=#{Symbiosis.prefix}")
    
    assert_equal 0, Process.wait(pid)
    assert_equal "domains-populated\n", result.args
    assert_equal "#{domain.name}\n", result.output
  end
end
