#
#  Makefile for the firewall package
#

nop:
	@echo "Makefile - available targets"
	@echo " "
	@echo " all       - generate rules and manpages"
	@echo " rules     - generate automatic rules"
	@echo " manpage   - generate manpage for ./bin/firewall"
	@echo " test      - test firewall installation"
	@echo " clean     - clean up"
	@echo " "

clean:
	if [ -d ./man ] ; then rm -rf ./man ; fi
	if [ -d ./i ] ; then rm -rf ./i ; fi

manpage: ./bin/firewall
	if ! [ -d ./man ] ; then mkdir ./man ; fi
	pod2man ./bin/firewall > ./man/firewall.1
	pod2man ./bin/firewall-logtail > ./man/firewall-logtail.1
	pod2man ./bin/firewall-blacklist > ./man/firewall-blacklist.1

all: manpage

test:
	if [ ! -d ./i ]; then mkdir ./i ; fi
	if [ ! -d ./i/incoming.d/ ]; then mkdir ./i/incoming.d/; fi
	if [ ! -d ./i/outgoing.d/ ]; then mkdir ./i/outgoing.d/; fi
	if [ ! -d ./i/blacklist.d/ ]; then mkdir ./i/blacklist.d/; fi
	touch ./i/incoming.d/00-ssh
	touch ./i/incoming.d/05-ping
	sudo ./bin/firewall --incoming-d=./i/incoming.d --outgoing-d=./i/outgoing.d/ --rule-d=./rule.d/ --no-exec --verbose --blacklist-d=./i/blacklist  --no-delete --verbose
