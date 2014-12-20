#!/usr/bin/env python3
# -*- coding: utf8 -*-

import sys
import redis
from   yaml import load
import json

def init(rdis, conf):
    print("=== users")
    maxid = 0; owners = {}

    # delete all users
    #[rdis.delete(k) for k in rdis.keys('u:*')]

    for user in conf.get('users'):
        userid = user.get('id')
        owners[user.get('name')] = userid
        user['id'] = userid
        print(user)

        rdis.set("u:{0}".format(userid), json.dumps(user, sort_keys=True, separators=(',',':'))) 
        rdis.set("u:{0}:id".format(user['name']), userid)
        maxid = max(maxid, userid)

    rdis.set("u:$", maxid+1)

    print("=== devices")
    #[rdis.delete(d) for d in rdis.keys('d:*')]

    devid = 1; users_devices = dict([(u['id'], []) for u in conf.get('users')])
    for device in conf.get('devices'):
        device['ownerid'] = owners[device['owner']]
        users_devices[device['ownerid']].append(devid)
        print(device)

        rdis.set("d:{0}".format(devid), json.dumps(device, sort_keys=True, separators=(',',':')))
        rdis.set("d:{0}:id".format(device['name']), devid)
        devid += 1

    rdis.set("d:$", devid+1)

    print("=== indexes")
    print("users devices: ", users_devices)
    for userid, devices in users_devices.items():
        rdis.delete("u:{0}:d".format(userid))

        if len(devices) > 0:
            rdis.rpush("u:{0}:d".format(userid), *devices)


if __name__ == '__main__':
    if len(sys.argv) != 2:
        print("Usage: {0} conf.yml".format(sys.argv[0])); sys.exit(1)

    rdis = redis.StrictRedis(host='localhost', port=6379, db=1)
    conf = load(open(sys.argv[1],'r'))
    #print(conf)

    # delete all the database
    rdis.flushdb()

    init(rdis, conf)

