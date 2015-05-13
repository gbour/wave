#!/usr/bin/env python
# -*- coding: utf8 -*-

import time
import gevent

from gevent import monkey
monkey.patch_time()

import logging
from nyamuk import nyamuk
from nyamuk.event import *
import nyamuk.nyamuk_const as NC

monkey.patch_socket()
monkey.patch_select()

def myfunc(a):
    print "{0}: started".format(a)
    time.sleep(5)
    print "{0}: stopped".format(a)


cur = 0
prev = 0
total = 0

def mqttcli(a):
    global cur, prev, total

    c = nyamuk.Nyamuk("gevt:{0}".format(a), None, None, 'localhost', log_level=logging.ERROR)
    ret = c.connect()
    cur +=1; total +=1

    if ret != NC.ERR_SUCCESS:
        return ret

    r = c.packet_write()
    r = c.loop()
    e = c.pop_event()
    #print e.ret_code # must be 0
    time.sleep(10)

    c.disconnect()
    c.packet_write()

    total -=1

limiter = 1000; #10
slotcount = 0;
firstblocked = True
rate = 0.005
ratec = 0.01

def monitor():
    global cur, prev, total
    global limiter, slotcount, firstblocked, rate, ratec

    while True:
        print "clients/s: {0}, connected: {1}".format(cur-prev, total)
        prev = cur
        time.sleep(1)

        if firstblocked and slotcount < limiter:
            ratec /= 2
            rate -= ratec
            print "not blocked", rate, slotcount
        slotcount = 0
        firstblocked = True

if __name__ == '__main__':
    m = gevent.spawn(monitor)
    m.start()
    print "monitor:", m

    jobs = []
    while len(jobs) < 1000:
        if slotcount >= limiter:
            print "blocked", rate
            # 
            if firstblocked:
                rate += ratec; firstblocked = False

            time.sleep(.25); continue

        jobs.append(gevent.spawn(mqttcli, len(jobs)))
        jobs[-1].start()
        slotcount += 1
        time.sleep(rate)

    print "#1000 jobs created" 
    gevent.joinall(jobs)
    m.kill()


