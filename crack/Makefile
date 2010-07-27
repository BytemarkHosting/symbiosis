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
docs:
	pod2man ./test-symbiosis-passwords > test-symbiosis-passwords.man
	pod2man ./passwd-test.c            > passwd-test.man

#
#  Clean
#
clean:
	-rm -f *.o *~ passwd-test *.man
