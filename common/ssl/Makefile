#!/usr/bin/make -f

HOSTNAME ?= $(shell hostname -f)
DAYS     ?= 3650

ifneq "$(HOSTNAME)" ""
SUBJECT  ?= /CN=$(HOSTNAME)
endif

tempext  := symbiosis.$(shell echo $$$$)

define check_key_with_certificate 
	@mode=`stat --format '%a' $(2)` ; \
	if [ '640' != "$$mode" ] ; then \
		echo "I: Changing mode on $(2) from $$mode to 640." ; \
		chmod 640 $(2) ; \
	else \
		echo "I: Mode on $(2) is $$mode."; \
	fi
	@group=`stat --format '%G' $(2)` ; \
	if [ "root" = "$$USERNAME" ] && [ "ssl-cert" != "$$group" ] ; then \
		echo "I: Changing group on $(2) from $$group to ssl-cert." ; \
		chgrp ssl-cert $(2) ; \
	fi
	@if [ "$$(openssl x509 -noout -modulus -in $(1) 2>/dev/null )" = "$$(openssl rsa -noout -modulus -in $(2))" ] ; then \
		echo "I: Successfully verified that the key in $(2) and certificate in $(1) match." ; \
	else \
		echo "W: The key in $(2) and certificate in $(1) do not match." ; \
	fi
	@if ( openssl x509 -in $(3) -noout > /dev/null 2>&1 ) ; then \
		if ( openssl verify -CAfile $(3) $(1)  > /dev/null 2>&1 ) ; then \
    	echo "I: Successfully verified $(3) with $(1)."; \
		else \
			echo "W: Cannot verify $(1) using $(3).  Maybe the bundle is wrong?" ; \
		fi ; \
	elif ( openssl verify -CAfile $(1) $(1) > /dev/null 2>&1  ) ; then \
   	echo "I: The certificate in $(1) is self-signed."; \
	else \
		echo "W: Cannot verify $(1).  Maybe a bundle is missing?" ; \
	fi
endef


check: check_crt_and_key check_combined

check_combined: ssl.combined
	$(call check_key_with_certificate,ssl.combined,ssl.combined,ssl.combined)

check_crt_and_key: ssl.crt ssl.key
	$(call check_key_with_certificate,ssl.crt,ssl.key,ssl.bundle)

ssl.csr: ssl.key
	@if [ -z "$(SUBJECT)" ]  ; then \
		echo "E: Could not determine certificate subject"; \
		exit 1 ; \
	fi
	@openssl req -subj "$(SUBJECT)" -new \
    -days $(DAYS) -key ssl.key -out ssl.csr.$(tempext) -sha256 > /dev/null
	@mv -b ssl.csr.$(tempext) ssl.csr
	@echo "I: Created a certifcate request."

ssl.crt: ssl.key
	@if [ -z "$(SUBJECT)" ]  ; then \
		echo "E: Could not determine certificate subject"; \
		exit 1 ; \
	fi
	@openssl req -subj "$(SUBJECT)" -new \
		-x509 -days 3650 -nodes -out ssl.crt.$(tempext) \
		-key ssl.key -sha256 > /dev/null
	@mv -b ssl.crt.$(tempext) ssl.crt
	@echo "I: Created a self-signed certificate."

ssl.key: 
	@openssl genrsa -out ssl.key.$(tempext) 2048
	@if [ "root" = "$$USERNAME" ] ; then \
		chgrp ssl-cert ssl.key.$(tempext) ; \
	fi
	@mv -b ssl.key.$(tempext) ssl.key
	@echo "I: Created a key."

ssl.combined: ssl.crt ssl.key 
	@cp ssl.crt ssl.combined.$(tempext)
	@if ( openssl x509 -in ssl.bundle -noout > /dev/null 2>&1 ) ; then \
		if ( openssl verify -CAfile ssl.bundle ssl.crt > /dev/null 2>&1 ) ; then \
			cat ssl.bundle >> ssl.combined.$(tempext) ; \
		else \
			echo "W: Cannot verify ssl.crt using ssl.bundle." ; \
		fi ; \
	fi
	@cat ssl.key >> ssl.combined.$(tempext)
	@mv -b ssl.combined.$(tempext) ssl.combined
	@echo "I: Created combined certificate, bundle, and key."

csr: ssl.csr
req: csr
request: csr

crt: ssl.crt
cert: crt
certificate: crt
self-signed-cert: crt
self-signed-certificate: crt

key: ssl.key

combined: ssl.combined

clean:
	@$(RM) -v ssl.crt.symbiosis.[0-9]* ssl.key.symbiosis.[0-9]* ssl.combined.symbiosis.[0-9]* 

.PHONY: clean check_crt check_combined check crt cert certifcate self-signed-cert self-signed-certifcate csr req request key combined
