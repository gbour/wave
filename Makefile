
APP=wave_app

all: build

build:
	./rebar prepare-deps

debug:
	erl -pa ebin/ `find deps -name ebin` -s $(APP) -s sync

test:
	cd tests && ./run

release:
	./rebar generate

clean:
	./rebar clean

.PHONY: test
