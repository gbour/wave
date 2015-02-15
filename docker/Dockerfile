
FROM correl/erlang
#FROM debian
MAINTAINER Guillaume Bour <guillaume@bour.cc>

RUN DEBIAN_FRONTEND=noninteractive apt-get update -qq && apt-get -y upgrade
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y \
	git \ 
	lua-redis \
	redis-server \
	redis-tools \
	supervisor

RUN rm -Rf /opt/wave && git clone https://github.com/gbour/wave.git /opt/wave
RUN cd /opt/wave && ./rebar prepare-deps

ADD supervisord.conf /etc/supervisord.conf

EXPOSE 1883 6379
ENTRYPOINT /usr/bin/supervisord
