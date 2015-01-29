#!/usr/bin/env python3
# -*- coding: utf8 -*-

# requirements
# - PySensors (not yet)
# - batinfo
#

# TODO: catch SIGTERM to disconnect
#       fetch system temperature

import sys
import json
import time
import psutil
import batinfo
import mosquitto

LOOP_DELAY = 5 # seconds
MQTT_ID   = 'pchealth'
MQTT_USER = ''
MQTT_PWD  = ''

def on_connect(m, obj, rc):
    print("connected") if rc == 0 else print("connection failure")

def hashme(obj, keys=('total','used','free'), norm=True):
    return dict([(k, round(obj.__getattribute__(k)/1024,2) if norm else obj.__getattribute__(k)) for k in keys])

def main(server, devicename):
    global LOOP_DELAY

    #1 - connects & register MQTT client
    c = mosquitto.Mosquitto(MQTT_ID + "/" + devicename)
    c.on_connect = on_connect

    try:
        c.connect(server[0], server[1], 60)
    except:
        print("failed to connect to {0}:{1} mqtt server".format(*server)); sys.exit(3)

    c.loop_start()

    #2 - loop & send measures
    while(True):
        cpu  = psutil.cpu_percent(interval=.5)
        mem  = hashme(psutil.virtual_memory())
        swap = hashme(psutil.swap_memory())
        net  = hashme(psutil.net_io_counters(), ('bytes_sent','bytes_recv'))
        batt = hashme(batinfo.battery(), ('capacity','status','charge_full','charge_now'), norm=False)
        print(cpu, mem, swap, net, batt)

        c.publish('/devices/xps13/metrics/cpu' , cpu, 0)
        c.publish('/devices/xps13/metrics/mem' , json.dumps(mem) , 0)
        c.publish('/devices/xps13/metrics/swap', json.dumps(swap), 0)
        c.publish('/devices/xps13/metrics/net' , json.dumps(net) , 0)
        c.publish('/devices/xps13/metrics/batt', json.dumps(batt), 0)
        time.sleep(LOOP_DELAY)


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: {0} [server:port] devicename"); sys.exit(1)

    server = ['localhost', 1883]
    if len(sys.argv) == 3:
        server = sys.argv[1].split(':')
        if len(server) == 2:
            try:
                server[1] = int(server[1])
            except ValueError:
                print("port is not an integer"); sys.exit(2)
        else:
            server = [server[0], 1883]

    main(server, sys.argv[-1])
