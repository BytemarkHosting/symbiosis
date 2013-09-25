#
#  Makefile for the updater package
#

all: manpage

nop:
	@echo "Available targets are:"
	@echo " "
	@echo " manpage - generate manpage"
	@echo " clean   - clean up"
	@echo " "

clean:
	rm -f *.1 || true

manpage:
	pod2man -r '' -c '' -n symbiosis-updater sbin/symbiosis-updater > symbiosis-updater.1

