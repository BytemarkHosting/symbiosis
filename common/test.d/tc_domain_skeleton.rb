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
    make_skeleton
  end

  def make_skeleton
    skelpath = Symbiosis.path_in_etc('symbiosis/skel')

    Symbiosis::Utils.mkdir_p skelpath

    Symbiosis::Utils.set_param 'test-param', 'this is a test', skelpath
    Symbiosis::Utils.set_param 'test/test-param', 'also a test', skelpath
    Symbiosis::Utils.set_param 'test/deep/test-param', 'deep test', skelpath

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

  def test_domainskeleton_hooks
    hooks_dir = Symbiosis.path_in_etc('symbiosis', 'skel-hooks.d')
    outputTestHelpers.make_test_hook hooks_dir

    domain = Symbiosis::Domain.new(nil, Symbiosis.prefix)
    domain.create

    result = Symbiosis::DomainSkeleton.run_hooks! domain.name

    assert_equal "domain-created\n", result.args
    assert_equal "#{domain.name}\n", result.output

    Symbiosis.rm_rf hooks_dir
  end
end
