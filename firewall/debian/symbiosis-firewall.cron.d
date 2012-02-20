# Crontab snippet which will invoke our iptables-based blocker to firewall
# away people who conduct dictionary attacks.
#
# We run every fifteen minutes deliberately so that we get a fair chance of
# catching a remote IP which makes multiple rejections in between our testing
# attempts.
#
# (Since we only process *new* logfile entries each time we start.)
#

5,20,35,50 * * * * root [ -x /usr/sbin/symbiosis-firewall-blacklist ] && /usr/sbin/symbiosis-firewall-blacklist

#
# Whitelist valid IP addresses every hour, but outside the scope of the
# firewall test.
#
10,25,40,55 * * * * root [ -x /usr/sbin/symbiosis-firewall-whitelist ] && /usr/sbin/symbiosis-firewall-whitelist

#
# Reload the firewall every hour.
#
@hourly root [ -x /usr/sbin/symbiosis-firewall ] && /usr/sbin/symbiosis-firewall 

