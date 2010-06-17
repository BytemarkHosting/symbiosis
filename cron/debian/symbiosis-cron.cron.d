# Run our wrapper once per minute, unless the binary has gone away.
*/1 * * * * root [ -x /sbin/symbiosis-crontab ] && /sbin/symbiosis-crontab
