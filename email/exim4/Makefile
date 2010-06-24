program      := $(notdir $(CURDIR))
conf         := $(program).conf
conf_tmp     := $(conf).tmp
snippets_dir := bytemark-vhost.d
snippets     := $(shell find $(CURDIR)/$(snippets_dir) -mindepth 1 -regextype posix-basic -type f -regex '.*/[a-z0-9][a-z0-9-]\+' | sort) 

ifeq ($(program),dovecot)
check_args = -a -c $(conf_tmp)
else ifeq ($(program),exim4)
check_args = -bV -C $(conf_tmp)
endif

all: $(conf)

$(conf): check
	@mv -fb $(conf_tmp) $(conf)

$(conf_tmp): distclean Makefile $(snippets)
	@for s in $(snippets) ; do \
	    echo "# ------------------------------------------------------------------------------" >>  $(conf_tmp)  ;\
	    echo "# $$s" >> $(conf_tmp)  ;\
	    echo "# ------------------------------------------------------------------------------" >>  $(conf_tmp)  ;\
	    echo >> $(conf_tmp)  ;\
	    cat $$s >> $(conf_tmp) ;\
	done

check: $(conf_tmp)
	@/usr/sbin/$(program) $(check_args) > /dev/null

distclean:
	@rm -f $(conf_tmp)

clean:
	@rm -f $(conf)

# We always want the temporary config to be remade.
.PHONY: $(conf_tmp) clean distclean check

.PRECIOUS: $(conf)
