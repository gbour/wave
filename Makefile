
SHELL=bash
APP=wave_app
TMPL_CFG=etc/wave.config

# debug build environment
# may be 'prod', 'dev' or 'travis' ('prod' by default)
# to run with another environment, enter:
# $> make env=myenv debug
env=prod

# blackbox tests debug mode
# 0: no debug
# 1: console debug
# '/my/file': debug written in '/my/file'
DEBUG=1

##
## -*- RULES -*-
##

all: init build setup

init:
	./rebar3 update

build:
	./rebar3 as $(env) compile

setup:
	# download/compile bbmustache
	./rebar3 as tmpl compile
	# generate config file for choosed environment
	./bin/build_dev_env $(TMPL_CFG) config/vars.$(env).config .wave.$(env).config

run: build setup
	# run application in choosed environment
	@echo "running in *$(env)* environment"
	erl -pa `find -L _build/$(env) -name ebin` -name 'wave@127.0.0.1' -setcookie wave -s $(APP) -s sync -config .wave.$(env).config -s observer -init debug +v

test:
	cd tests && DEBUG=$(DEBUG) PYTHONPATH=./nyamuk:./twotp ./run

release: setup
	./rebar3 as $(env) tar


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
