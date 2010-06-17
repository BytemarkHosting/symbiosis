

clean:
	rm wrapper/symbiosis-crontab || true
	rm manpages/*.1 || true

binary:	wrapper/symbiosis-crontab.c
	gcc -Wall -o wrapper/symbiosis-crontab wrapper/symbiosis-crontab.c


man:
	pod2man ./manpages/symbiosis-crontab.pod > ./manpages/symbiosis-crontab.1

