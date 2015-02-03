
APP=wave_app
CFG=etc/wave

all: build

build:
	./rebar prepare-deps

debug:
	erl -pa ebin/ `find deps -name ebin` -s $(APP) -s sync -config $(CFG)

test:
	cd tests && PYTHONPATH=./nyamuk ./run

release:
	./rebar generate

clean:
	./rebar clean

.PHONY: test
