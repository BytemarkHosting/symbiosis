# Encoding: UTF-8
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
    File.chown(1000, 1000, @prefix)
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
    txt = config.generate_config
    spf_records = txt.split($/).select{|l| l =~ basic_spf_record_match}
    assert_not_equal([], spf_records, "SPF record(s) not found when custom SPF record was set")

    #
    # The make sure our spf record is matched.
    #
    spf_records.each do |r|
      assert_match(/^'#{Regexp.escape(@domain.name)}:#{Regexp.escape(spf_record.gsub(":",'\\\\072'))}:/, r)
    end

  end

  def test_bytemark_antispam
    #
    # This now ignores this flag, as the service has been withdrawn
    #
    @domain.__send__(:set_param,"bytemark-antispam", true, @domain.config_dir)
    config = Symbiosis::ConfigFiles::Tinydns.new(nil, "#")
    config.domain = @domain
    config.template = @dns_template
    assert(!@domain.uses_bytemark_antispam?)

    txt = config.generate_config

    assert_no_match(/^@#{Regexp.escape(@domain.name)}::a\.nospam\.bytemark\.co\.uk/,txt, "No line mentions a.nospam.bytemark.co.uk")
    assert_no_match(/^@#{Regexp.escape(@domain.name)}::b\.nospam\.bytemark\.co\.uk/,txt, "No line mentions b.nospam.bytemark.co.uk")
  end

  def test_srv_generation
    target = "\\000\\012\\000d\\023\\304\\003pbx\\007example\\003com\\000"
    target_decoded = @domain.__send__(:tinydns_decode, target)

    result = @domain.srv_record_for(10,100,5060,"pbx.example.com")
    result_decoded = @domain.__send__(:tinydns_decode, result)

    assert_equal(target_decoded,result_decoded)
  end
  
  def test_set_ttl
    config = Symbiosis::ConfigFiles::Tinydns.new(nil, "#")
    config.domain = @domain
    config.template = @dns_template

    #
    # The default TTL for Symbiosis is 5 minutes
    #
    assert_equal(300, @domain.ttl, "Wrong default TTL returned")

    #
    # Minimum TTL is 60s, max is 86400s.
    #
    @domain.__send__(:set_param, "ttl", "5", @domain.config_dir)
    assert_equal(60, @domain.ttl, "Domain has wrong minimum TTL") 
    
    @domain.__send__(:set_param, "ttl", "5123123123123123123123123", @domain.config_dir)
    assert_equal(86400, @domain.ttl, "Domain has wrong maximum TTL") 


    #
    # Make sure there are no SPF records by default.
    #
    @domain.__send__(:set_param, "ttl", nil, @domain.config_dir)
    txt = config.generate_config.split($/)
    ns_records = txt.select{|t| t =~ /^\./}

    assert_match(/:300$/m, ns_records.first, "NS records have incorect TTL when no custom TTL is set")

    #
    # Now set the TTL to something else
    #
    @domain.__send__(:set_param, "ttl", "12345", @domain.config_dir)
    txt = config.generate_config.split($/)
    ns_records = txt.select{|t| t =~ /^\./}

    assert_match(/:12345$/m, ns_records.first, "NS records have incorrect TTL when custom TTL is set")

  end

  def test_dmarc
    assert(!@domain.has_dmarc?)

    #
    # Test the default record
    #
    @domain.__send__(:set_param,'dmarc',true, @domain.config_dir)
    assert(@domain.has_dmarc?)
    assert_equal("v=DMARC1; p=quarantine; sp=none", @domain.dmarc_record)
   
    #
    # Test a user-defined record 
    #
    @domain.__send__(:set_param,'dmarc',"v=DMARC1; p=reject; pct=100; rua=mailto:postmaster@dmarcdomain.com", @domain.config_dir)
    assert_equal("v=DMARC1; p=reject; pct=100; rua=mailto\\072postmaster\\100dmarcdomain.com", @domain.dmarc_record)

    #
    # Now test the template
    #
    config = Symbiosis::ConfigFiles::Tinydns.new(nil, "#")
    config.domain = @domain
    config.template = @dns_template
    txt = config.generate_config

    assert_match(/^'_dmarc.#{Regexp.escape(@domain.name)}:v=DMARC1; p=reject; pct=100; rua=mailto\\072postmaster\\100dmarcdomain\.com:300$/,txt, "")
  end

end
