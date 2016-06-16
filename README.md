wave [![Build Status](https://secure.travis-ci.org/gbour/wave.png?branch=master)](http://travis-ci.org/gbour/wave) ![release 0.3.0](https://img.shields.io/badge/release-0.3.0-red.svg)
====

Wave is a MQTT Broker, written in Erlang.   
It implements most of MQTT features, and currently supports TCP and SSL transports (and soon WebSockets)

You can try it on **[iot.bour.cc](http://iot.bour.cc)**.  
A Docker image is also available on **[Docker hub](https://hub.docker.com/r/gbour/wave)**.

Features
--------

* [x] MQTT v1.3
* [x] MQTT v1.3.1
* [x] Qos 0, 1 & 2
* [x] SSL
* [x] WebSockets
* [ ] $SYS hierarchy
* [ ] monitoring
* [ ] access logs
* [ ] authentication
* [ ] administration interface
* [ ] plugins



Quickstart
----------

### Checkout, build & run

prerequisites:
* redis
* erlang >= 17.2


```
$> git clone https://github.com/gbour/wave.git wave
$> cd wave && make
# 'make cert' generates sample self-signed certificate, required to start wave with default configuration
# you can alternatively provide your own
$> make cert
$> make run
```

NOTE: the build process is also generating a default self-signed certificate that you can replace later


### Docker image

Alternatively, you can use docker image available on Docker hub (along with official redis image):
```
$> docker pull redis:alpine
$> docker run --name redis-wave -d redis:alpine

$> docker pull gbour/wave:websockets
$> docker run --name wave -d --link=redis-wave -p 1883:1883 -p 8883:8883 gbour/wave:websockets
```

### Give it a try
Now, you can try using ie mosquitto tools:
```
$> mosquitto_sub -h localhost -t foo/bar -v&
$> mosquitto_pub -h localhost -t foo/bar -m 'is it working?'
foo/bar is it working
```

Authors
-------

Main developer: Guillaume Bour &lt;guillaume@bour.cc&gt;

License
-------

**Wave** is distributed under AGPLv3 license.

