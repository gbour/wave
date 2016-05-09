#!/bin/bash
# -*- coding: UTF8 -*-

echo "** starting erlang wave server"
erl -pa `find -L _build/travis -name ebin` -s wave_app -config .wave.travis.config -noinput -name 'wave@127.0.0.1' -setcookie wave&
PID=$!
echo " pid= $PID"
sleep 10

make DEBUG=/tmp/wave.tests.log WAVELOGS=/tmp/wave.travis.log test
STATUS=$?

kill -HUP $PID

exit $STATUS
