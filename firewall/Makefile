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
	make -C ext clean
	$(RM) ext/Makefile


man/%.man: ./bin/%
	[ -d man ] || mkdir man
	RUBYLIB=./lib $<  --help | sed -e 's/^=\+$$//' | txt2man -s 1 -t $(notdir $<) | sed -e 's/\\\\fB/\\fB/' > $@


manpage: ./bin/firewall man/firewall-whitelist.man
	if ! [ -d ./man ] ; then mkdir ./man ; fi
	pod2man ./bin/firewall > ./man/firewall.1
	pod2man ./bin/firewall-logtail > ./man/firewall-logtail.1
	pod2man ./bin/firewall-blacklist > ./man/firewall-blacklist.1

all: manpage ext/symbiosis_utmp.so

distclean: clean

test: ext/symbiosis_utmp.so
	cd test && ruby ./tc_symbiosis_utmp.rb
	if [ ! -d ./i ]; then mkdir ./i ; fi
	if [ ! -d ./i/incoming.d/ ]; then mkdir ./i/incoming.d/; fi
	if [ ! -d ./i/outgoing.d/ ]; then mkdir ./i/outgoing.d/; fi
	if [ ! -d ./i/blacklist.d/ ]; then mkdir ./i/blacklist.d/; fi
	touch ./i/incoming.d/00-ssh
	touch ./i/incoming.d/05-ping
	fakeroot ./bin/firewall --incoming-d=./i/incoming.d --outgoing-d=./i/outgoing.d/ --rule-d=./rule.d/ --no-exec --verbose --blacklist-d=./i/blacklist.d --whitelist-d=./i/whitelist.d  --no-delete --verbose


ext/symbiosis_utmp.so: ext/Makefile
	make -C ext $(notdir $@)

ext/Makefile: ext/extconf.rb
	cd ext/ && ruby $(notdir $<)

.PHONY: test
