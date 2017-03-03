#
#  Makefile for the backup package
#
test:
	@echo "I: No tests available for this package"

clean:
	$(RM) -r ./debian/symbiosis-backup/usr/share/lintian/overrides

all:
	mkdir -p ./debian/symbiosis-backup/usr/share/lintian/overrides || true
	cp debian/lintian-overrides ./debian/symbiosis-backup/usr/share/lintian/overrides/symbiosis-backup

.PHONY: clean all test
