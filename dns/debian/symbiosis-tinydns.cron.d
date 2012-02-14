#
#  Ensure that we upload our file once per day, regardless of any
# changes or not.
#

0 0 * * * root  [ -x /usr/sbin/symbiosis-dns-generate ] && /usr/sbin/symbiosis-dns-generate --upload

#
#  Run four times per-hour and upload if changed
#
07,24,37,54 * * * * root [ -x /usr/sbin/symbiosis-dns-generate ] && /usr/sbin/symbiosis-dns-generate
