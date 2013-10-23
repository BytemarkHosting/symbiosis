$:.unshift  "../lib/" if File.directory?("../lib")

require 'test/unit'
require 'tmpdir'
require 'symbiosis/domain/dkim'

class DkimTest < Test::Unit::TestCase

  def setup
    @prefix = Dir.mktmpdir("srv")
    @prefix.freeze
    @domain = Symbiosis::Domain.new(nil, @prefix)
    @domain.create
  end

  def teardown
    unless $DEBUG
      @domain.destroy  if @domain.is_a?( Symbiosis::Domain)
      FileUtils.rm_rf(@prefix) if File.directory?(@prefix)
    end
  end

  def rsa_private_key_pem
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

  def rsa_public_key_pem
  <<EOF
-----BEGIN PUBLIC KEY-----
MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQCuLPyxujsFxJj5ZmvNPsk88kCT
sq71/HkwBw+F3IJUjfKUgakXo9y60qzCqyUauro9gYdKcstwr+5nIDKlAAn5cyTi
NgDqOLc5ROZ2s/hIfB4/P9qj+kENhWYovEIRi6kuCGVEtTLKc0OboNrFUQ0r40FJ
rGdVsVMB3cRcF0mVgQIDAQAB
-----END PUBLIC KEY-----
EOF
  end

  def rsa_public_key_txt
    "MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQCuLPyxujsFxJj5ZmvNPsk88kCTsq71/HkwBw+F3IJUjfKUgakXo9y60qzCqyUauro9gYdKcstwr+5nIDKlAAn5cyTiNgDqOLc5ROZ2s/hIfB4/P9qj+kENhWYovEIRi6kuCGVEtTLKc0OboNrFUQ0r40FJrGdVsVMB3cRcF0mVgQIDAQAB"
  end

  def rsa_private_key
    OpenSSL::PKey::RSA.new(rsa_private_key_pem)
  end

  def rsa_public_key
    OpenSSL::PKey::RSA.new(rsa_public_key_pem)
  end

  #####
  #
  # Tests
  #
  #####

  def test_dkim_selector
    @domain.__send__(:set_param,"dkim", false, @domain.config_dir)
    assert_equal(nil, @domain.dkim_selector)

    @domain.__send__(:set_param,"dkim", true, @domain.config_dir)

    #
    # This should return (in order) the first component of mailname, hostname,
    # or # $(hostname)
    #
    hostname = `uname -n`.chomp

    unless hostname.include?(".")
      require 'socket'
      begin
        hostname = Socket.gethostbyname(hostname).first
      rescue SocketError
        hostname = ""
      end
    end

    hostname = "default" if hostname.empty?

    assert_equal(hostname, @domain.dkim_selector)

    @domain.__send__(:set_param,"dkim", "foo", @domain.config_dir)
    assert_equal("foo", @domain.dkim_selector)
  end

  def test_dkim_public_key_b64
    @domain.__send__(:set_param,"dkim.key", rsa_private_key_pem, @domain.config_dir)
    assert_equal(rsa_private_key_pem, @domain.dkim_key.to_pem)
    assert_equal(rsa_public_key_txt, @domain.dkim_public_key_b64)
  end

end
