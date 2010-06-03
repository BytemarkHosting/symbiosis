#
#  Makefile for the backup package
#

nop:
	@echo "Makefile - available targets"
	@echo " "
	@echo " all       - generate manpage"
	@echo " clean     - clean up"
	@echo " "

clean:
	true

all:
	mkdir -p ./debian/symbiosis-backup/usr/share/lintian/overrides || true
	cp debian/lintian-overrides ./debian/symbiosis-backup/usr/share/lintian/overrides/symbiosis-backup

