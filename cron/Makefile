
all: binary man

clean:
	$(RM) wrapper/symbiosis-all-crontabs
	$(RM) man/*.man

binary: wrapper/symbiosis-all-crontabs

man: man/symbiosis-all-crontabs.man man/symbiosis-crontab.man

wrapper/symbiosis-all-crontabs:	wrapper/symbiosis-all-crontabs.c
	gcc -Wall -o wrapper/symbiosis-all-crontabs wrapper/symbiosis-all-crontabs.c

%.man: %.txt
	txt2man -s 1 -t $(basename $(notdir $<)) $< | sed -e 's/\\\\fB/\\fB/' > $@

.PHONY: binary clean man all
