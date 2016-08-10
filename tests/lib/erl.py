# -*- coding: utf8 -*-

from lib              import env
from twotp            import to_python, Atom, Tuple
from twotp.term       import List
from twisted.internet import defer


def fun(module, function, arguments=None, retval=None):
    @defer.inlineCallbacks
    def _erlfun(*args):
        ret = yield env.remote(module, function, *args)
        defer.returnValue(ret)

    return _erlfun

#
# erl emulation layer
#
class Record(object):
    def __init__(self, raw_data, defs):
        self._fields = defs[to_python(raw_data[0])]
        if len(self._fields) + 1 != len(raw_data):
            print 'smth went wrong'; return

        for i in xrange(len(self._fields)):
            setattr(self, self._fields[i], raw_data[i+1])

class ErlO(object):
    @staticmethod
    def erl(module, function, fmt=None, *args):
        erl_func = fun(module, function, *args)

        def _d(func):
            @defer.inlineCallbacks
            def _w(*args, **kwargs):
                ret = yield erl_func(*func(*args, **kwargs))
                if fmt is not None:
                    ret = fmt(ret)
                defer.returnValue(ret)
            return _w
        return _d


class process(ErlO):
    @staticmethod
    @ErlO.erl('erlang', 'is_process_alive', fmt=lambda x: True if x == Atom('true') else False)
    def alive(proc):
        return [proc]

    @staticmethod
    @ErlO.erl('erlang', 'exit')
    def kill(pid):
        return [pid, Atom('kill')]

class application(ErlO):
    @staticmethod
    @ErlO.erl('application', 'get_env')
    def get_env(app, param):
        return [Atom(app), Atom(param)]

    @staticmethod
    @ErlO.erl('application', 'set_env')
    def set_auth(required=False, filename='none'):
        return [Atom('wave'), Atom('auth'), [
            Tuple([Atom('required'), Atom(str(required).lower())]),
            Tuple([Atom('file'),     filename]),
        ]]

    @staticmethod
    @ErlO.erl('application', 'set_env')
    def set_acl(enabled=False, filename='none'):
        return [Atom('wave'), Atom('acl'), [
            Tuple([Atom('enabled'), Atom(str(enabled).lower())]),
            Tuple([Atom('file'),    filename]),
        ]]

class supervisor(ErlO):
    @staticmethod
    @ErlO.erl('supervisor', 'count_children', fmt=lambda x: [val for (key, val) in x if key == Atom('active')][0])
    def count(name):
        return [Atom(name)]

class sessions(ErlO):
    records = {
        'session': ['deviceid','topics','transport','opts','pingid','keepalive','inflight','next_msgid','will'],
        # wave_websocket state
        'state'  : ['parent','child','child_state','in_buf'],
    }

    @staticmethod
    @ErlO.erl('supervisor', 'which_children', fmt=lambda x: [pid for (a,pid,b,c) in x])
    def workers():
        return [Atom('wave_sessions_sup')]

    @staticmethod
    @ErlO.erl('sys', 'get_state', fmt=lambda x: Record(x[1], sessions.records))
    def state(sess_pid):
        return [sess_pid]

    @staticmethod
    @ErlO.erl('wave_websocket', 'debug_getstate', fmt=lambda x: Record(x, sessions.records))
    def ws_state(ws_pid):
        return [ws_pid]

class auth(ErlO):
    @staticmethod
    @ErlO.erl('wave_auth','switch')
    def switch(filename):
        return [filename]

class acl(ErlO):
    @staticmethod
    @ErlO.erl('wave_acl', 'switch')
    def switch(filename):
        return [filename]

class exometer(ErlO):
    @staticmethod
    @ErlO.erl('exometer', 'get_value', fmt=lambda x: dict(to_python(x[1])))
    def value(key):
        def _enc(x):
            try:
                x = int(x)
            except:
                x = Atom(x)

            return x

        return [[_enc(k) for k in key.split('.')]]

    @staticmethod
    @ErlO.erl('exometer_report', 'list_reporters', fmt=lambda x: dict(to_python(x)))
    def reporters():
        return []

    @staticmethod
    @ErlO.erl('exometer_report', 'list_subscriptions',
              fmt=lambda x: dict([('.'.join([str(x) for x in name]), dps) for (name, dps, delay, args) in to_python(x)]))
    def subscriptions(reporter):
        return [Atom(reporter)]

