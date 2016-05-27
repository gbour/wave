FROM msaraiva/erlang
MAINTAINER Guillaume Bour <guillaume@bour.cc>

RUN apk update && \
    apk add libstdc++ && \
    # wave or dependencies required modules
    apk add erlang-sasl erlang-inets erlang-crypto erlang-ssl erlang-public-key erlang-asn1 erlang-mnesia erlang-syntax-tools

#
# wave is store in /opt/wave
#   lib/ contains libraries
#   wave.config is the configuration files

#   entrypoint.sh is the startuo script (stored in /usr/local/bin)
#
RUN mkdir -p /opt/wave
COPY _build/alpine /opt/wave/
COPY .wave.alpine.config /opt/wave/wave.config
COPY tools/docker/entrypoint.sh /usr/local/bin

# MQTT ports
EXPOSE 1883 8883

ENTRYPOINT ["entrypoint.sh"]
