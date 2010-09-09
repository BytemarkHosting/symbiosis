#
# Crontab snippet to scan /srv for new symlinks and writes a config file for
# exim for domain rewrites.
#

*/1 * * * * Debian-exim [ -x /usr/sbin/exim_rewrite_scan ] && /usr/sbin/exim_rewrite_scan  /etc/exim4/exim4.conf

