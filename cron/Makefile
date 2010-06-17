
all: binary man

clean:
	$(RM) wrapper/symbiosis-crontab || true
	$(RM) manpages/*.1 || true

binary:	wrapper/symbiosis-crontab.c
	gcc -Wall -o wrapper/symbiosis-crontab wrapper/symbiosis-crontab.c

man:
	pod2man ./manpages/symbiosis-crontab.pod > ./manpages/symbiosis-crontab.1

.PHONY: binary clean man all
