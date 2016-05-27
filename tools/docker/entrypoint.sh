#!/bin/sh
# -*- coding: UTF8 -*-

erl -pa `find -L /opt/wave/lib -name ebin` \
    -name 'wave@127.0.0.1' -setcookie wave -s wave_app \
    -config /opt/wave/wave.config -noshell \
    -kernel inet_dist_listen_min 44001 inet_dist_listen_max 44001

