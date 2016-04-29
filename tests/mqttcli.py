#!/usr/bin/env python
# -*- coding: UTF8 -*-

import os
import time
import random
import logging
from nyamuk import nyamuk
from nyamuk.event import *
import nyamuk.nyamuk_const as NC
from nyamuk.mqtt_pkt import MqttPkt

class MqttClient(object):
    def __init__(self, prefix, rand=True, connect=False, raw_connect=False, **kwargs):
        loglevel = logging.DEBUG; logfile = None

        DEBUG   = os.environ.get('DEBUG', '0')
        if DEBUG == '0':
            loglevel  = logging.WARNING
        elif DEBUG != '1':
            logfile   = DEBUG

        server = 'localhost'

        self._c = nyamuk.Nyamuk("test:{0}:{1}".format(prefix, random.randint(0,9999) if rand else 0),
            None, None, server=server, log_level=loglevel, log_file=logfile, **kwargs)

        # MQTT connection
        # 
        # connect takes protocol version (3 or 4) or is True (set version to 3)
        if connect is not False:
            version = connect if isinstance(connect, int) else 3
            self.connect(version=version)
            return

        # open TCP connection
        #
        port = 1883
        if raw_connect:
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            try:
                sock.connect((server, port))
                sock.setsockopt(socket.SOL_SOCKET, socket.SO_KEEPALIVE, 1)
                sock.setblocking(1)
                #sock.settimeout(.5)
            except Exception as e:
                raise e

            self._c.sock = sock

    def disconnect(self):
        self._c.disconnect(); self._c.packet_write()

    def do(self, action, *args, **kwargs):
        read_response = kwargs.pop('read_response', True)
        retcode = getattr(self._c, action)(*args, **kwargs)

        if retcode != NC.ERR_SUCCESS:
            return retcode

        r = self._c.packet_write()
        r = self._c.loop()

        if not read_response:
            return retcode # NC.ERR_SUCCESS

        return self._c.pop_event()

    def clientid(self):
        return self._c.client_id

    def get_last_mid(self):
        return self._c.get_last_mid()

    def conn_is_alive(self):
        return self._c.conn_is_alive()

    def recv(self):
        self._c.loop()
        return self._c.pop_event()

    def __getattr__(self, name):
        def _(*args, **kwargs):
            return self.do(name, *args, **kwargs)
            
        return _

    #
    # forge a "raw" MQTT packet, and send it
    #
    # fields: list of tuples (type, value)
    # ie: [('str', "MQTT"),('bytes', 
    def forge(self, command, flags, fields, send=False):
        rlen = 0
        for (xtype, value) in fields:
            if xtype == 'string':
                rlen += len(value) + 2 # 2 = uint16 = storing string len
            elif xtype == 'byte':
                rlen += 1
            elif xtype == 'uint16':
                rlen += 2
            elif xtype == 'bytes':
                rlen += len(value)

        pkt = MqttPkt()
        pkt.command = command | flags
        pkt.remaining_length = rlen
        pkt.alloc()

        for (xtype, value) in fields:
            if xtype == 'bytes':
                pkt.write_bytes(value, len(value))
            else:
                getattr(pkt, "write_"+xtype)(value)

        if not send:
            return
        return self.packet_queue(pkt)

    # quite of "unproper" release
    # force TCP socket to close immediatly
    def destroy(self):
        self._c.sock.shutdown(socket.SHUT_RDWR)
        self._c.sock.close()

