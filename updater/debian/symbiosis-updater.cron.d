#
# Update the system, for new Symbiosis packages and security updates.
# 
# This should happen between 9.30 and 10.30 (given a random sleep), Monday to
# Friday.

30 9 * * 1-5 root [ -x /usr/sbin/symbiosis-updater ] && /usr/sbin/symbiosis-updater
