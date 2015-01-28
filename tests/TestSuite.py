#!/usr/bin/env python
# -*- coding: UTF8 -*-

import inspect
import traceback
import subprocess

p = subprocess.Popen(['tput', 'cols'], stdout=subprocess.PIPE)
WIDTH = int(p.stdout.read()[:-1])

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
            traceback.print_exc()

            return False
    return _

class TestSuite(object):
    def __init__(self, suitename):
        self.suitename = suitename

    def run(self):
        print "\n\033[1m... {0} ...\033[0m".format(self.suitename)

        tests = [(name, meth) for (name, meth) in inspect.getmembers(self, predicate=inspect.ismethod) if name.startswith('test_')]
        for (name, test) in tests:
            (desc, ret) = test()
            if ret:
                self.passed(desc)
            else:
                self.failed(desc)

    def passed(self, testname):
        print "{0}{1}[\033[92mPASSED\033[0m]".format(testname, ' '*(WIDTH-10-len(testname)))

    def failed(self, testname):
        print "{0}{1}[\033[91mFAILED\033[0m]".format(testname, ' '*(WIDTH-10-len(testname)))

#    @desc("this is the 1st test")
#    def test_01(self):
#        return True
#
#    @desc("this is 2d test")
#    def test_02(self):
#        return False
