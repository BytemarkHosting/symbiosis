#
#  Makefile for the updateer package
#

nop:
	@echo "Available targets are:"
	@echo " "
	@echo " manpage - generate manpage"
	@echo " clean   - clean up"
	@echo " "

clean:
	rm -f *.1 || true

manpage:
	pod2man usr/bin/symbiosis-updater > symbiosis-updater.1

