#
#  Install backup2l configuration file.
#

install:
	mkdir -p  ${prefix}/usr/share/bytemark-vhost-simple-backup/
	cp backup2l.conf ${prefix}/usr/share/bytemark-vhost-simple-backup/backup2l.conf
	chmod 644 ${prefix}/usr/share/bytemark-vhost-simple-backup/backup2l.conf

clean:
	-find . -name '*~' -delete
	-rm build-stamp configure-stamp
