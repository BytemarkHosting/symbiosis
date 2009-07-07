#
#  Flags & options
#
CC=gcc
CFLAGS=-g -O2 -Wall
LDFLAGS=

#
#  Make
#
passwd-test: passwd-test.o
	$(CC) $(LDFLAGS) -o $@ -lcrack $^
	strip passwd-test

install:
	mkdir -p $(PREFIX)
	cp passwd-test $(PREFIX)
	cp vhost-test-passwords $(PREFIX)

#
#  Clean
#
clean:
	-rm -f *.o *~ passwd-test configure-stamp build-stamp
