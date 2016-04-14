
SHELL=bash
APP=wave_app
TMPL_CFG=etc/wave.config
DEV_VARS=config/vars.dev.config
DEV_CFG=.wave.dev

all: init build

init:
	./rebar3 update

build:
	./rebar3 as prod compile

debug:
	./rebar3 as dev compile
	# generate config file for local dev environment
	./bin/build_dev_env $(TMPL_CFG) $(DEV_VARS) $(DEV_CFG).config
	# run application in local dev env
	erl -pa `find -L _build/dev -name ebin` -s $(APP) -s sync -config $(DEV_CFG) -s observer -init debug +v

test:
	cd tests && DEBUG=1 PYTHONPATH=./nyamuk ./run

release:
	./rebar3 release

dialyze:
	if [[ "$$TRAVIS_OTP_RELEASE" > "18" ]]; then\
		./rebar3 dialyzer;\
	fi

clean:
	./rebar3 clean

cert:
	openssl req -x509 -newkey rsa:2048 -keyout ./etc/wave_key.pem -out ./etc/wave_cert.pem -days 365 \
		-nodes \
		-subj '/CN=FR/O=wave/CN=wave.acme.org'

msc:
	find docs/ -iname *.msc | xargs -I '{}' /opt/mscgenx/bin/msc-gen -T png  '{}'

## testing freemobile sms module
## faking a ssh connection
test_sms:
	mosquitto_pub -t '/secu/ssh' -m '{"action": "login", "user":"luke", "server": "darkstar", "from":"tatooine", "at": "year 0"}'


.PHONY: test
