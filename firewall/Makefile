#
#  Makefile for the firewall package
#

nop:
	@echo "Makefile - available targets"
	@echo " "
	@echo " all       - generate rules and manpages"
	@echo " rules     - generate automatic rules"
	@echo " manpages  - generate manpages for ./bin/firewall"
	@echo " test      - test firewall installation"
	@echo " clean     - clean up"
	@echo " "

clean:
	if [ -d ./manpages ] ; then rm -rf ./manpages ; fi
	if [ -d ./i ] ; then rm -rf ./i ; fi
	cd ext && ruby extconf.rb
	make -C ext clean
	$(RM) ext/Makefile


manpages/%.man: ./sbin/%
	[ -d ./manpages ] || mkdir ./manpages
	RUBYLIB=./lib $<  --help | sed -e 's/^=\+$$//' | txt2man -s 1 -t $(notdir $<) | sed -e 's/\\\\fB/\\fB/' > $@

manpages/%.1: ./bin/%
	[ -d ./manpages ] || mkdir ./manpages
	pod2man -s 1 $< > $@ 

manpages: ./manpages/symbiosis-firewall-whitelist.man ./manpages/symbiosis-firewall.man ./manpages/firewall.1 ./manpages/firewall-logtail.1 ./manpages/firewall-blacklist.1

all: manpages ext/symbiosis_utmp.so

distclean: clean

test: ext/symbiosis_utmp.so
	@cd test && ruby ./ts_firewall.rb
	@if [ ! -d ./i ]; then mkdir ./i ; fi
	@if [ ! -d ./i/incoming.d/ ]; then mkdir ./i/incoming.d/; fi
	@if [ ! -d ./i/outgoing.d/ ]; then mkdir ./i/outgoing.d/; fi
	@if [ ! -d ./i/blacklist.d/ ]; then mkdir ./i/blacklist.d/; fi
	@if [ ! -d ./i/whitelist.d/ ]; then mkdir ./i/whitelist.d/; fi
	@if [ ! -d ./i/local.d/ ]; then mkdir ./i/local.d/; fi
	@touch  i/whitelist.d/192.168.1.100
	@touch  i/whitelist.d/2001:1af:123:00::1
	@touch  i/blacklist.d/192.168.1.101
	@touch  i/blacklist.d/2001:1af:123:00::2
	@touch  i/incoming.d/00-established
	@touch  i/incoming.d/00-related
	@touch  i/incoming.d/05-ping
	@touch  i/incoming.d/07-ssh
	@touch  i/incoming.d/10-http
	@touch  i/incoming.d/15-https
	@touch  i/incoming.d/20-ftp
	@touch  i/incoming.d/30-imap
	@touch  i/incoming.d/40-imaps
	@touch  i/incoming.d/50-pop3
	@touch  i/incoming.d/60-pop3s
	@touch  i/incoming.d/70-smtp
	@touch  i/incoming.d/75-ntp
	@touch  i/incoming.d/80-smtps
	@touch  i/incoming.d/85-submission
	@touch  i/incoming.d/90-sieve
	@touch  i/incoming.d/99-reject
	@touch  i/outgoing.d/00-established
	@touch  i/outgoing.d/00-related
	@touch  i/outgoing.d/10-match-uid-not-www-data
	@echo "212.110.161.177" > i/outgoing.d/20-match-uid-www-data
	@echo "2001:41c8:20:862:ac1:1::" >> i/outgoing.d/20-match-uid-www-data
	@touch  i/outgoing.d/99-reject
#	fakeroot ./bin/firewall --incoming-d=./i/incoming.d --outgoing-d=./i/outgoing.d/ --rule-d=./rule.d/ --no-exec --verbose --blacklist-d=./i/blacklist.d --whitelist-d=./i/whitelist.d  --no-delete --verbose
	@ruby -I lib ./sbin/symbiosis-firewall -b ./i -T rule.d -x -v -d

ext/symbiosis_utmp.so: ext/Makefile
	make -C ext $(notdir $@)

ext/Makefile: ext/extconf.rb
	cd ext/ && ruby $(notdir $<)

.PHONY: test manpages all clean distclean
