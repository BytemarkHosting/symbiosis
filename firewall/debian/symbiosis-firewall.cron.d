# Crontab snippet which will invoke our firewall-based blocker to firewall
# away people who conduct dictionary attacks.
#
# We run every fifteen minutes deliberately so that we get a fair chance of
# catching a remote IP which makes multiple rejections in between our testing
# attempts.
#
# (Since we only process *new* logfile entries each time we start.)
#

*/15 * * * * root [ -x /usr/bin/firewall-blacklist ] && /usr/bin/firewall-blacklist

#
#  Whitelist valid IP addresses every hour, but outside the scope of the
# firewall test.
#
30   * * * * root [ -x /usr/sbin/symbiosis-firewall-whitelist ] && /usr/sbin/symbiosis-firewall-whitelist


#
# Check the firewall works every hour.
#
# ourly      root [ -x /usr/sbin/symbiosis-firewall ] && /usr/sbin/

