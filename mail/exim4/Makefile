exim4_conf         := exim4.conf
exim4_conf_tmp     := $(exim4_conf).tmp 
exim4_snippets_dir := bytemark-vhost.d
exim4_snippets     := $(shell find $$PWD/$(exim4_snippets_dir) -mindepth 1 -regextype posix-basic -type f -regex '.*/[a-z0-9][a-z0-9-]\+' | sort) 

all: $(exim4_conf)

$(exim4_conf_tmp): Makefile $(exim4_snippets)
	@rm -f $(exim4_conf_tmp)
	@for s in $(exim4_snippets) ; do \
	    echo "# ------------------------------------------------------------------------------" >>  $(exim4_conf_tmp)  ;\
	    echo "# $$s" >> $(exim4_conf_tmp)  ;\
	    echo "# ------------------------------------------------------------------------------" >>  $(exim4_conf_tmp)  ;\
	    echo >> $(exim4_conf_tmp)  ;\
	    cat $$s >> $(exim4_conf_tmp) ;\
	done
	@/usr/sbin/exim4 -bV -C $(exim4_conf_tmp) > /dev/null

$(exim4_conf): $(exim4_conf_tmp)
	@mv -fb $(exim4_conf_tmp) $(exim4_conf)

clean:
	@rm -f $(exim4_conf)

.PHONY:  clean

.PRECIOUS: $(exim4_conf)
