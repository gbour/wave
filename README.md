wave [![Build Status](https://secure.travis-ci.org/gbour/wave.png)](http://travis-ci.org/gbour/wave)
====

MQTT Broker

SSL
---

Application supports SSL
 1. generates a certificate with **make cert**
 2. MQTT SSL port is configured in *etc/wave.config* (defaults to **8883**)

It allows only TLSv1.1 and TLSv1.2 versions, and (EC)DHE ciphers (currently hardcoded).

You can test using mosquitto client:

    $> mosquitto_sub -t 'foo/bar' --tls-version tlsv1.2 --cafile etc/wave_cert.pem -d -v -p 8883 --insecure
