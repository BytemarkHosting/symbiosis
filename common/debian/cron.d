#
#  Test the strength of user passwords.
#
#  Output will be sent to root by email.
#

# hourly check
@hourly root [ -x /usr/sbin/symbiosis-password-test ] && /usr/sbin/symbiosis-password-test --hourly

# weekly check
@weekly root [ -x /usr/sbin/symbiosis-password-test ] && /usr/sbin/symbiosis-password-test --weekly

# daily check of SSL certificates
@daily root [ -x /usr/bin/symbiosis-ssl ] && /usr/bin/symbiosis-ssl
