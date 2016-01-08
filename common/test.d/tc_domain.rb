# encoding: UTF-8

require 'test/unit'
require 'tmpdir'
require 'symbiosis/domain'

class TestDomain < Test::Unit::TestCase

  include Symbiosis

  def test_check_password
    password = "foo"
    bad_password = "bar"

    domain = Domain.new()

    #
    # Run a set of tests against the password three times
    #
    [[ password, "not" ],
     [ password.crypt("ab"),"DES"],
     [ password.crypt("$1$abc$"), "glibc2" ]].each do |crypt_password, method|

      #
      # The normal check.
      #
      assert( domain.check_password(password, crypt_password), 
        "correct password was not accepted (#{method} crypted)")
      #
      # Not for bad passwords.
      #
      assert( !domain.check_password(bad_password, crypt_password), 
        "bad password was accepted (#{method} crypted)")

      #
      # Don't do the reminaining tests against plain-text passwords
      #
      next if method == "not" 

      #
      # Make sure if someone gives a the correct crypt as the password, we
      # don't authenticate.  However this can't be done for the straight DES
      # crypt, providing a loophole.
      #
      assert( !domain.check_password(crypt_password, crypt_password), 
        "crypt'd password was accepted (#{method} crypted)") unless method == "DES"

      #
      # Prepend the password with CRYPT -- this should force the crypt comparison.
      #
      crypt_password_with_prefix = "{CRYPT}"+crypt_password

      assert( domain.check_password(password, crypt_password_with_prefix), 
        "correct password was not accepted (#{method} crypted with CRYPT prefix)")

      #
      # Check with a lower-case crypt, just in case.
      #
      crypt_password_with_prefix = "{crypt}"+crypt_password
      assert( domain.check_password(password, crypt_password_with_prefix), 
        "correct password was not accepted (#{method} crypted with crypt prefix)")

      #
      # Don't accept bad passwords.
      #
      assert( !domain.check_password(bad_password, crypt_password_with_prefix),
       "bad password was accepted (#{method} crypted with CRYPT prefix)")

      #
      # Make sure we don't accept the crypt'd password via straight string comparison
      #
      assert( !domain.check_password(crypt_password, crypt_password_with_prefix),
       "crypt'd password was accepted (#{method} crypted with CRYPT prefix)")

      #
      # Make sure we don't accept the crypt'd password with a prefix via straight string comparison
      #
      assert( !domain.check_password(crypt_password_with_prefix, crypt_password_with_prefix), 
        "crypt'd password with CRYPT prefix was accepted (#{method} crypted with CRYPT prefix)")


    end

  end

  def test_password_with_foreign_shit
    utf8_password = "ábë"
    domain = Domain.new()

    %w(UTF-8 ISO-8859-1).each do |enc|
      if utf8_password.respond_to?(:encode)
        password = utf8_password.encode(enc)
      else
        require 'iconv' unless defined?(Iconv)
        password = Iconv.conv(enc, "UTF-8", utf8_password)
      end

      #
      # Make sure the UTF-8 password works.
      #
      assert(domain.check_password(password, password))

      #
      # Now crypy+check
      #
      des_crypt_password = password.crypt("ab")
      assert(domain.check_password(password, des_crypt_password), "Correct password not accepted, DES crypt, #{enc} encoding.")
  
      #
      # glibc
      #
      glibc2_crypt_password = password.crypt("$1$ab$")
      assert(domain.check_password(password, glibc2_crypt_password), "Correct password not accepted, glibc2 crypt, #{enc} encoding.")
    end

  end

  def test_xckd_password
    domain = Domain.new()
    password = "correct horse battery staple"

    assert(domain.check_password(password, password))

    des_crypt_password = password.crypt("ab")
    assert(domain.check_password(password, des_crypt_password), "Correct xkcd password not accepted, DES crypt.")

    glibc2_crypt_password = password.crypt("$1$ab$")
    assert(domain.check_password(password, glibc2_crypt_password), "Correct xkcd password not accepted, glibc2 crypt.")


  end

  def test_ips
    domain = Domain.new()

    domain.ips
  end

  def test_crypt_password
    domain = Domain.new()
    password = "correct horse battery staple"

    assert_match(/^{CRYPT}\$6\$.{8,8}\$/,domain.crypt_password(password), "Text password not crypted correctly (with SHA512)")

    password = "{CRYPT}asdasdads"
    assert_equal(domain.crypt_password(password),password, "Password with {CRYPT} at the beginning gets re-hashed.")

    password = "$1$asda$asdawdasda"
    assert_match(/^{CRYPT}/, domain.crypt_password(password), "Password with salt at the beginning doesn't get CRYPT pre-pended")
    assert_equal(domain.crypt_password(password),"{CRYPT}"+password, "Password with salt at the beginning gets re-hashed.")
  end

  def test_aliases
    #
    # This tmpdir gets destroyed at the end of the block.
    #
    Dir.mktmpdir do |prefix|
      #
      # This shouldn't happen (tm).
      #
      assert(File.exist?(prefix), "Temporary directory missing")

      domain = Domain.new(nil, prefix)
      FileUtils.mkdir_p(domain.directory)
      
      #
      # By default just the www.domain should be returned by Domain#aliases
      #
      aliases = [ "www."+domain.name ]

      assert_equal([], aliases - domain.aliases, 
        "Not all aliases returned by Symbiosis::Domain#aliases after a single domain was created.")
      assert_equal([], domain.aliases - aliases, 
        "Too many all aliases returned by Symbiosis::Domain#aliases after a single domain was created.")

      symlinked_domain =  Domain.new(nil, prefix) 
      FileUtils.ln_s(domain.directory, symlinked_domain.directory)

      #
      # We should get the domain, with "www." on the front, plus the symlinked domain.
      #
      aliases += [
        symlinked_domain.name,
        "www."+symlinked_domain.name
      ]

      assert_equal([], aliases - domain.aliases, 
        "not all aliases returned by Symbiosis::Domain#aliases")
      assert_equal([], domain.aliases - aliases, 
        "Too many aliases returned by Symbiosis::Domain#aliases")
      
      #
      # Create another new domain
      #
      other_domain = Domain.new(nil, prefix)
      FileUtils.mkdir_p(other_domain.directory)

      #
      # We should get just this new www.other_domain back
      #
      assert_equal([], ["www."+other_domain.name] - other_domain.aliases)

      #
      # And we should get the same answer as before for the original domain.
      #
      assert_equal([], aliases - domain.aliases, 
        "Not all aliases returned by Symbiosis::Domain#aliases after a separate domain was created.")
      assert_equal([], domain.aliases - aliases, 
        "Too many all aliases returned by Symbiosis::Domain#aliases after a separate domain was created.")
      
      #
      # Now create a dangling symlink
      #
      FileUtils.ln_s(File.join(prefix, "nonexistent.com"), symlinked_domain.directory)

      #
      # We should get the same thing back
      #
      assert_equal([], aliases - domain.aliases,
        "not all aliases returned by Symbiosis::Domain#aliases after a dangling symlink was created.")
      assert_equal([], domain.aliases - aliases, 
        "Too many aliases returned by Symbiosis::Domain#aliases after a dangling symlink was created.")


      #
      # Now make a www.other_domain directory.  This should now not return www.domain as an alias.
      #
      FileUtils.mkdir_p(File.join(prefix, "www."+other_domain.name))
      assert_equal([], other_domain.aliases, "www.other_domain returned as an alias to other_domain, when it exists in its own right.")
      
    end
  end

end
