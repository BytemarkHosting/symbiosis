#
#  Ensure that we upload our file once per day, regardless of any
# changes or not.
#

0 0 * * * root  [ -x /sbin/symbiosis-dns-generate ]; && /sbin/symbiosis-dns-generate --force

#
#  Run once per-hour and upload if changed
#
17 * * * * root [ -x /sbin/symbiosis-dns-generate ]; && /sbin/symbiosis-dns-generate
