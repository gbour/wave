
APP=wave_app
CFG=etc/wave

all: build

build:
	./rebar prepare-deps

debug:
	erl -pa ebin/ `find deps -name ebin` -s $(APP) -s sync -config $(CFG) -s observer

test:
	cd tests && DEBUG=1 PYTHONPATH=./nyamuk ./run

release:
	./rebar generate

clean:
	./rebar clean

cert:
	openssl req -x509 -newkey rsa:2048 -keyout ./etc/wave_key.pem -out ./etc/wave_cert.pem -days 365 \
		-nodes \
		-subj '/CN=FR/O=wave/CN=wave.acme.org'

.PHONY: test
