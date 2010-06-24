#
#  Flags & options
#
CC=gcc
CFLAGS=-g -O2 -Wall
LDFLAGS=

all: passwd-test docs

#
#  Make
#
passwd-test: passwd-test.o
	$(CC) $(LDFLAGS) -o $@ -lcrack $^
	strip passwd-test

#
# Documentation
#
docs: vhost-test-passwords.man

vhost-test-passwords.man:
	pod2man ./vhost-test-passwords > vhost-test-passwords.man

#
#  Clean
#
clean:
	-rm -f *.o *~ passwd-test vhost-test-passwords.man
	-rm vhost-test-passwords.1