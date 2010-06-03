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
	rm -f update-packages.1 || true

all:
	pod2man update-packages.pod > update-packages.1

