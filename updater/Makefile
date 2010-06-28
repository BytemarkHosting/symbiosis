#
#  Makefile for the updateer package
#

nop:
	@echo "Makefile - available targets"
	@echo " "
	@echo " all       - generate manpage"
	@echo " clean     - clean up"
	@echo " "

clean:
	rm -f *.1 || true

all:
	pod2man symbiosis-updater.pod > symbiosis-updater.1

