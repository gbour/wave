
APP=wave_app

build:
	./rebar prepare-deps

debug:
	erl -pa ebin/ `find deps -name ebin` -s $(APP) -s sync

release:
	./rebar generate

clean:
	./rebar clean
