#!/bin/bash
# -*- coding: UTF8 -*-

echo "** starting erlang wave server"
erl -pa ebin/ `find deps -name ebin` -s wave_app -config etc/wave.config -noinput &
PID=$!
echo " pid= $PID"
sleep 10

make test
STATUS=$?

kill -HUP $PID

exit $STATUS
