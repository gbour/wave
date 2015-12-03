#!/bin/bash
# -*- coding: UTF8 -*-

echo "** starting erlang wave server"
erl -pa `find _build -name ebin` -s wave_app -config wave.travis.config -noinput &
PID=$!
echo " pid= $PID"
sleep 10

make test
STATUS=$?

kill -HUP $PID

exit $STATUS
