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
# Check the firewall works every hour.
#
@hourly      root [ -x /usr/bin/firewall ] && /usr/bin/firewall --test

