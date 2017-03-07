FROM debian:stretch

COPY ./autotest/test.d/conf/autotest-sources.list /etc/apt/sources.list.d/

RUN apt-get update && apt-get install -y devscripts graphviz rake

COPY . /symbiosis
RUN apt-key add /symbiosis/symbiosis-common-sources.key

WORKDIR /symbiosis
RUN for proj in *; do [ -f "$proj/debian/control" ] && mk-build-deps -t 'apt-get --no-install-recommends -y'  -ir $proj/debian/control; done

RUN apt-get install --allow-unauthenticated -y $(grep '^[[:space:]]*TEST_DEPS' .gitlab-ci.yml | sed -e 's/[[:space:]]*TEST_DEPS: //')

RUN adduser --home=/srv --shell=/bin/bash --no-create-home --disabled-login --gecos='Symbiosis Administrator,,,' admin && chown admin.admin /srv
