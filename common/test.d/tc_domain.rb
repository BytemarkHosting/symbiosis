
require 'test/unit'

require 'symbiosis/domain'

class TestDomain < Test::Unit::TestCase

  include Symbiosis

  def test_check_password
    password = "foo"
    bad_password = "bar"

    domain = Domain.new("test")

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


end
