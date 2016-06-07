
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

clean-all:
	./rebar3 clean -a
	rm -Rf `find _build -name priv`


cert:
	openssl req -x509 -newkey rsa:2048 -keyout ./etc/wave_key.pem -out ./etc/wave_cert.pem -days 365 \
		-nodes \
		-subj '/CN=FR/O=wave/CN=wave.acme.org'

msc:
	find docs/ -iname *.msc | xargs -I '{}' /opt/mscgenx/bin/msc-gen -T png  '{}'

#
# build docker image used to compile wave
docker-init:
	docker build -f tools/docker/Dockerfile.build -t gbour/wave-build .

# compile wave with previous image
docker-build:
	# NIF not automatically rebuilded
	rm -Rf _build/default/lib/jiffy/{ebin,priv}
	docker run --rm -ti -v ${PWD}:${PWD} -w ${PWD} -u `id -u`:`id -g` -e HOME=${PWD} wave-build make env=alpine

# build docker target image
# NOTE: tar is used to solve symlinks in build profile lib/ directory
docker-pack:
	tar czh . | docker build -f tools/docker/Dockerfile -t wave -

#
# NOTE: SSL certificates are not embedded in the images
#       we use those stored in etc/ directory (-v parameter)
docker-run:
	# ignore error is redis already started
	-docker run --name redis-wave -d redis:alpine
	docker run --name wave --rm --link=redis-wave -v ${PWD}/.docker-logs:/var/log -v ${PWD}/etc:/opt/wave/etc -p 1883:1883 -p 8883:8883 wave

## testing freemobile sms module
## faking a ssh connection
test_sms:
	mosquitto_pub -t '/secu/ssh' -m '{"action": "login", "user":"luke", "server": "darkstar", "from":"tatooine", "at": "year 0"}'

.PHONY: test
