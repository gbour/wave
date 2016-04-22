#!/usr/bin/env python
# -*- coding: UTF8 -*-

import sys
import inspect
import traceback
import subprocess

p = subprocess.Popen(["stty","size"], stdout=subprocess.PIPE)
WIDTH = int(p.stdout.read()[:-1].split(' ')[-1])

DISPLAY = {
    True  : (92, "PASSED" , True),
    False : (91, "FAILED" , False),
    'skip': (93, "SKIPPED", True)
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

class TestSuite(object):
    def __init__(self, suitename):
        self.suitename = suitename

    def run(self, testfilter):
        status = True
        counters = {'passed':0, 'failed': 0, 'skipped': 0}

        print "\n\033[1m... {0} ...\033[0m".format(self.suitename)

        tests = [(name, meth) for (name, meth) in inspect.getmembers(self, predicate=inspect.ismethod) if name.startswith('test_')]
        for (name, test) in tests:
            if testfilter and not testfilter in name:
                continue

            ret = test()
            try:
                (desc, ret) = ret
            except:
                desc   = self.__module__ + "." + name

            self._print(DISPLAY[ret], name, desc)

            counters[DISPLAY[ret][1].lower()] += 1
            status &= DISPLAY[ret][-1]

        return (status, counters)

    def _print(self, (color, text, _ign), testname):
        print "{0}{1}[\033[{2}m{3}\033[0m]".format(testname, ' '*(WIDTH-10-len(testname)), color, text)
#    @desc("this is the 1st test")
#    def test_01(self):
#        return True
#
#    @desc("this is 2d test")
#    def test_02(self):
#        return False
