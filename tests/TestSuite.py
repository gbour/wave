#!/usr/bin/env python
# -*- coding: UTF8 -*-

import sys
import inspect
import logging
import traceback
import subprocess
from twisted.internet import defer, reactor

from lib import env

p = subprocess.Popen(["stty","size"], stdout=subprocess.PIPE)
WIDTH = int(p.stdout.read()[:-1].split(' ')[-1])

DISPLAY = {
    True  : ("1;32", "PASSED" , True),
    False : ("3;31", "FAILED" , False),
    'skip': ("1;33", "SKIPPED", True)
}

# test functions decorator
def desc(name):
    def _decorator(func):
        def _wrapper(self):
            return (name, func(self))
        return _wrapper
    return _decorator

def catch(func):
    def _(self):
        try:
            return func(self)
        except Exception, e:
            traceback.print_exc(file=sys.stderr)
            return False
    return _

def skip(fun):
    def _(self):
        return 'skip'
    return _


@defer.inlineCallbacks
def clean_states():
    """ cleaning server state (db, internals) between each test """
    env.db.flushdb()
    yield env.twotp.callRemote('wave@127.0.0.1', 'wave_app', 'debug_cleanup')
    #defer.returnValue(None)


class TestSuite(object):
    def __init__(self, suitename):
        self.suitename = suitename

    def cleanup(self):
        pass

    @defer.inlineCallbacks
    def run(self, testfilter):
        status = True
        counters = {'passed':0, 'failed': 0, 'skipped': 0}

        fname = inspect.getfile(self.__class__).replace('.','/',).split('/')[-2]
        logging.info("\n\033[1m... {0}: {1} ...\033[0m".format(fname, self.suitename))

        tests = [(name, meth) for (name, meth) in inspect.getmembers(self, predicate=inspect.ismethod) if name.startswith('test_')]
        for (name, test) in tests:
            if testfilter and not testfilter in name:
                continue

            yield clean_states()
            logging.debug(">> "+name)
            ret = test()
            try:
                (desc, ret) = ret
            except:
                desc   = self.__module__ + "." + name

            if isinstance(ret, defer.Deferred):
                ret = yield ret

            self._print(DISPLAY[ret], name, desc)

            counters[DISPLAY[ret][1].lower()] += 1
            status &= DISPLAY[ret][-1]

        yield self.cleanup()
        defer.returnValue((status, counters))

    def _print(self, (color, text, _ign), funcname, testname):
        #print "{0}{1}[\033[{2}m{3}\033[0m]".format(testname, ' '*(WIDTH-10-len(testname)), color, text)

        logging.info("{fun}: {name}{halign}[\033[{color}m{status}\033[0m]".format(
            fun    = funcname,
            name   = testname,
            halign = ' '*(WIDTH-11-len(testname+funcname)),
            color  = color,
            status = text
        ))

