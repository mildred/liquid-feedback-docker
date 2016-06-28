#
# Dockerfile for liquid-feedback
#

FROM debian:jessie

MAINTAINER Pedro Ângelo <pangelo@void.io>

ENV LF_CORE_VERSION 3.2.2
ENV LF_FEND_VERSION 3.2.1
ENV LF_WMCP_VERSION 2.1.0
ENV LF_MOONBRIDGE_VERSION 1.0.1

#
# install dependencies
#

RUN apt-get update && apt-get -y install \
        build-essential \
        exim4 \
        pmake \
        curl \
        imagemagick \
        liblua5.2-dev \
        libpq-dev \
        lighttpd \
        lua5.2 \
        mercurial \
        postgresql \
        postgresql-server-dev-9.4 \
        python-pip \
    && pip install markdown2

RUN DEBIAN_FRONTEND=noninteractive apt-get -y install libbsd-dev

#
# prepare file tree
#


RUN mkdir -p /opt/lf/sources/patches \
             /opt/lf/sources/scripts \
             /opt/lf/bin

RUN cd /opt/lf/sources \
    && hg clone -u v${LF_CORE_VERSION} http://www.public-software-group.org/mercurial/liquid_feedback_core/ ./core \
    && hg clone -u v${LF_FEND_VERSION} http://www.public-software-group.org/mercurial/liquid_feedback_frontend/ ./frontend \
    && hg clone -u v${LF_WMCP_VERSION} http://www.public-software-group.org/mercurial/webmcp ./webmcp \
    && hg clone -u v${LF_MOONBRIDGE_VERSION} http://www.public-software-group.org/mercurial/moonbridge ./moonbridge

#
# build core
#

RUN cd /opt/lf/sources/core \
    && make \
    && cp lf_update lf_update_issue_order lf_update_suggestion_order /opt/lf/bin

#
# build Moonbridge
#

RUN cd /opt/lf/sources/moonbridge \
    && pmake MOONBR_LUA_PATH=/opt/lf/moonbridge/?.lua \
    && cp -R /opt/lf/sources/moonbridge /opt/lf/moonbridge

#
# build WebMCP
#

RUN cd /opt/lf/sources/webmcp \
    && make \
    && mkdir /opt/lf/webmcp \
    && cp -RL framework/* /opt/lf/webmcp

#
# build frontend
#

RUN cd /opt/lf/ \
    && cd /opt/lf/sources/frontend \
    && hg archive -t files /opt/lf/frontend \
    && cd /opt/lf/frontend/fastpath \
    && make \
    && chown www-data /opt/lf/frontend/tmp

#
# setup db
#

#WORKDIR /opt/lf

COPY ./scripts/setup_db.sql /opt/lf/sources/scripts/
COPY ./scripts/config_db.sql /opt/lf/sources/scripts/

RUN  cp /opt/lf/sources/core/core.sql /opt/lf/core.sql
RUN  cp -R /opt/lf/sources/core/update/ /opt/lf/update
#COPY scripts/core.sql.patch /opt/lf/
#RUN patch /opt/lf/core.sql /opt/lf/core.sql.patch
#RUN  cp /opt/lf/sources/core/core.sql /opt/lf/core.sql.orig

RUN addgroup --system lf \
    && adduser --system --ingroup lf --no-create-home --disabled-password lf \
    && service postgresql start \
    && (su -l postgres -c "psql -f /opt/lf/sources/scripts/setup_db.sql") \
    && (su -l postgres -c "psql -f /opt/lf/sources/core/core.sql liquid_feedback") \
    && (su -l postgres -c "psql -f /opt/lf/sources/scripts/config_db.sql liquid_feedback") \
    && service postgresql stop

#
# cleanup
#

RUN rm -rf /opt/lf/sources \
    && apt-get -y purge \
        pmake \
        build-essential \
        liblua5.1-0-dev \
        libpq-dev \
        mercurial \
        postgresql-server-dev-9.4 \
        python-pip \
    && apt-get -y autoremove \
    && apt-get clean

#
# configure everything
#

# TODO: configure mail system

RUN DEBIAN_FRONTEND=noninteractive apt-get install -y ssmtp

# webserver config
COPY ./scripts/60-liquidfeedback.conf /etc/lighttpd/conf-available/

RUN ln -s /etc/lighttpd/conf-available/60-liquidfeedback.conf /etc/lighttpd/conf-enabled/60-lighttpd.conf

# app config
COPY ./scripts/lfconfig.lua /opt/lf/frontend/config/

# update script
COPY ./scripts/lf_updated /opt/lf/bin/

# startup script
COPY ./scripts/start.sh /opt/lf/bin/

#
# ready to go
#

EXPOSE 8080

WORKDIR /opt/lf/frontend

ENTRYPOINT ["/opt/lf/bin/start.sh"]

