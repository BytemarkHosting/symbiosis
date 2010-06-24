# Run our wrapper once per minute, unless the binary has gone away.
*/1 * * * * root [ -x /usr/sbin/symbiosis-all-crontabs ] && /usr/sbin/symbiosis-all-crontabs
