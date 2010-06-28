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
	pod2man symbiosis-update.pod > symbiosis-update.1

