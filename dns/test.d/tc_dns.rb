$:.unshift  "../lib/" if File.directory?("../lib")
$:.unshift  "../../common/lib" if File.directory?("../../common/lib")

require 'test/unit'
require 'tmpdir'
require 'symbiosis/domain'
require 'symbiosis/domain/dns'
require 'symbiosis/config_files/tinydns'
require 'erb'

class DnsTest < Test::Unit::TestCase

  def setup
    @prefix = Dir.mktmpdir("srv")
    @prefix.freeze
    @domain = Symbiosis::Domain.new(nil, @prefix)
    @domain.create

    @dns_template = "../dns.d/tinydns.template.erb"
  end

  def teardown
    unless $DEBUG
      @domain.destroy  if @domain.is_a?( Symbiosis::Domain)
      FileUtils.rm_rf(@prefix) if File.directory?(@prefix)
    end
  end

  def dkim_private_key_pem
  <<EOF
-----BEGIN RSA PRIVATE KEY-----
MIICWwIBAAKBgQCuLPyxujsFxJj5ZmvNPsk88kCTsq71/HkwBw+F3IJUjfKUgakX
o9y60qzCqyUauro9gYdKcstwr+5nIDKlAAn5cyTiNgDqOLc5ROZ2s/hIfB4/P9qj
+kENhWYovEIRi6kuCGVEtTLKc0OboNrFUQ0r40FJrGdVsVMB3cRcF0mVgQIDAQAB
AoGAIM8Wln/nCFIdIrWZTuMp0xIq+edpr6psRZC+6s87uaO3cyPtbyeNt59hrZXB
eoR7+oQAsRRooARz2vcksxILzqKc4K/OGrrAv8eCJMWjBNKqc8sgI5vyHNxj7DN5
7+0LL5MY3g+CMSSDmfnHavfE3sR+vfPLxDs5yH2o6c8t6iUCQQDg6bb+cVotf3R2
GL4IEBumv2YbEpMOLufAX5c8DyoB3g5rQfoOmcQogtnrjjea78qAbrvh2OlkrnRk
k4buzADnAkEAxj/+jkmwKynyYfoH5FZHoeUshAdR481zC+jhmZ6lcwrgm8fhB1od
hhEFHeOWYCmlSubokTlWhopjY3h4QPyhVwJABuNBZmNkRpZro544W5jar+2Wm+ei
t0F6eWqz//Pa7nm1aVV46e+NkUwIjm0piMYlJm+9sznoU9v/1oCqFjALKwJAHoES
RgqIlNurc+/o7vVnqD1/EAGgVBD0tsxqihyjEISH8vBaa6suB8bupp6yMLG3wUKu
XkoYSjNY/6E1v6ofmQJARctrCu4TVpu3kf9UHbmTDvORTEZVwf8QNxbuWuxQ4q6N
zft9X7eB5Lxw67aY+AeKmZlV8uor1+pkrBgUmwsY6Q==
-----END RSA PRIVATE KEY-----
EOF
  end

  def dkim_public_key_txt
    "MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQCuLPyxujsFxJj5ZmvNPsk88kCTsq71/HkwBw+F3IJUjfKUgakXo9y60qzCqyUauro9gYdKcstwr+5nIDKlAAn5cyTiNgDqOLc5ROZ2s/hIfB4/P9qj+kENhWYovEIRi6kuCGVEtTLKc0OboNrFUQ0r40FJrGdVsVMB3cRcF0mVgQIDAQAB"
  end

  def dkim_private_key
    OpenSSL::PKey::RSA.new(dkim_private_key_pem)
  end

  def dkim_public_key
    OpenSSL::PKey::RSA.new(dkim_public_key_pem)
  end

  #####
  #
  # Tests
  #
  #####

  def test_dkim_record
    config = Symbiosis::ConfigFiles::Tinydns.new(nil, "#")
    config.domain = @domain
    config.template = @dns_template

    basic_dkim_record_match = /^'.*v=DKIM1.*/i

    #
    # Make sure no lines have v=DKIM1 in them.
    #
    txt = config.generate_config
    dkim_records = txt.split($/).select{|l| l =~ basic_dkim_record_match}
    assert_equal([], dkim_records, "DKIM record(s) found when no DKIM parameters were set")

    #
    # Set the DKIM key, but no selector.
    #
    @domain.__send__(:set_param,"dkim.key", dkim_private_key_pem, @domain.config_dir)

    #
    # Again, make sure no lines have v=DKIM1 in them.
    #
    txt = config.generate_config
    dkim_records = txt.split($/).select{|l| l =~ basic_dkim_record_match}
    assert_equal([], dkim_records, "DKIM record(s) found when a DKIM key was set, but without a selector")

    #
    # Now set the default selector
    #
    @domain.__send__(:set_param,"dkim", true, @domain.config_dir)
    txt = config.generate_config
    dkim_records = txt.split($/).select{|l| l =~ basic_dkim_record_match}
    assert_not_equal([], dkim_records, "No DKIM record(s) found when DKIM key and default selector was set")

    #
    # Now check the records we found
    #
    specific_dkim_record_match = /^'#{Regexp.escape(@domain.dkim_selector+"._domainkey."+@domain.name)}:[^:]*p=#{Regexp.escape(dkim_public_key_txt)}[^:]*(:.+)?/i
    dkim_records.each do |r|
      assert_match(specific_dkim_record_match, r,  "Incorrect DKIM record found when DKIM parameters were set")
    end

    #
    # Now change the selector, and make sure this comes through
    #
    pretend_selector = "this.is.a.pretend.selector"
    @domain.__send__(:set_param,"dkim", pretend_selector, @domain.config_dir)
    txt = config.generate_config
    dkim_records = txt.split($/).select{|l| l =~ basic_dkim_record_match}
    assert_not_equal([], dkim_records, "No DKIM record(s) found when DKIM key and default selector was set")

    #
    # Now check the records we found
    #
    specific_dkim_record_match = /^'#{Regexp.escape(pretend_selector+"._domainkey."+@domain.name)}:[^:]*p=#{Regexp.escape(dkim_public_key_txt)}[^:]*(:.+)?/i
    dkim_records.each do |r|
      assert_match(specific_dkim_record_match, r,  "Incorrect DKIM record found when DKIM parameters were set")
    end
  end

  def test_spf_record
    config = Symbiosis::ConfigFiles::Tinydns.new(nil, "#")
    config.domain = @domain
    config.template = @dns_template

    basic_spf_record_match = /^'.*v=spf.*/i

    #
    # Make sure there are no SPF records by default.
    #
    txt = config.generate_config
    spf_records = txt.split($/).select{|l| l =~ basic_spf_record_match}
    assert_equal([], spf_records, "SPF record(s) found when no SPF parameters were set")

    @domain.__send__(:set_param,"spf", true, @domain.config_dir)
    txt = config.generate_config
    spf_records = txt.split($/).select{|l| l =~ basic_spf_record_match}
    assert_not_equal([], spf_records, "SPF record(s) not found when SPF flag was set")

    #
    # The default SPF record should not cause fails or soft fails.
    #
    spf_records.each do |r|
      assert_no_match(/:v=spf1[^:]+[~-]all[^:]*:/, r, "Default record is too strict, and might cause unexpected bounces")
    end

    #
    # Now stick a different record in.
    #
    spf_record = "v=spf1 ip6:2001:41c8:1:2:3::4 -all"
    encoded_spf_record = "ip6:2001:41c8:1:2:3::4 -all"
    encoded_spf_record = "v=spf1 ip6\\0721080\\072\\0728\\072800\\07268/96 -all"
    @domain.__send__(:set_param,"spf", spf_record, @domain.config_dir)
    @domain.__send__(:tinydns_encode,spf_record)
    txt = config.generate_config
    spf_records = txt.split($/).select{|l| l =~ basic_spf_record_match}
    assert_not_equal([], spf_records, "SPF record(s) not found when custom SPF record was set")

    #
    # The make sure our spf record is matched.
    #
    spf_records.each do |r|
      assert_match(/^'#{Regexp.escape(@domain.name)}:#{Regexp.escape(spf_record.gsub(":","\\072"))}:/, r, "Default record is too strict, and might cause unexpected bounces")
    end

  end

end
