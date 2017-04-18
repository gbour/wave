# -*- coding: UTF8 -*-

import os
import types
import tempfile

from lib import env
from lib.env import debug
from lib.erl import application as app, auth, acl
from TestSuite import *
from mqttcli import MqttClient
from nyamuk.event import *

from twisted.internet import defer


class Acl(TestSuite):
    def __init__(self):
        TestSuite.__init__(self, "Acl")

    @defer.inlineCallbacks
    def setup_suite(self):
        ## configuring auth
        (fd, auth_file) = tempfile.mkstemp(prefix='wave-auth-'); os.close(fd)
        print "auth file:", auth_file
        with open(auth_file, 'w') as f:
            f.write(
"""ctrl:$2a$12$4xhMVs/zgy6T/GZobBAdc.bpbL2yaXnckX5YE9z5abEnGzsSaIeGq
foo:$2a$12$EwUNtApVj6j2z9VQlMf98O8Xc.650HdRFK6Rr4sVG6bc/tdjjgXOW
""")
        yield app.set_auth(required=True, filename=auth_file)
        yield auth.switch(auth_file)

        ## configuring acls
        (fd, acl_file) = tempfile.mkstemp(prefix='wave-acl-'); os.close(fd)
        print "acl file:", acl_file

        with open(acl_file, 'w') as f:
            f.write("""
# testsuite acl file
ctrl\tallow\tr\ttest/#

anonymous\tallow\tr\ttest/anonymous/sub/1
anonymous\tallow\tr\ttest/anonymous/sub/2/+
anonymous\tallow\tw\ttest/anonymous/pub/1
anonymous\tallow\tw\ttest/anonymous/pub/2/#

foo\tallow\tr\ttest/foo/sub/1
foo\tallow\tr\ttest/foo/sub/2/+
foo\tallow\tw\ttest/foo/pub/1
foo\tallow\tw\ttest/foo/pub/2/#
""")

        users = {
            'anonymous': {'user': None , 'password': None},
            'foo':       {'user': 'foo', 'password': 'bar'},
        }



        i = 1
        for user in sorted(users.keys()):
            @defer.inlineCallbacks
            def _init1(self):
                yield app.set_acl(enabled=False)

                defer.returnValue(self._t_check(client=user, acl=False, **users[user]))
            setattr(self, "test_{0:03}".format(i), types.MethodType(catch(desc(
                "user '{0}', no acl".format(user))(
                _init1)), self))

            i += 1
            @defer.inlineCallbacks
            def _init2(self):
                yield app.set_acl(enabled=True, filename=acl_file); yield acl.switch(acl_file)

                defer.returnValue(self._t_check(client=user, acl=True, **users[user]))
            setattr(self, "test_{0:03}".format(i), types.MethodType(catch(desc(
                "user '{0}', acls enabled".format(user))(
                _init2)), self))

            i += 1

    @defer.inlineCallbacks
    def cleanup_suite(self):
        yield app.set_auth(required=False)
        yield app.set_acl(enabled=False)


#    @defer.inlineCallbacks
    def _t_check(self, client, acl, user, password):
        ctrl = MqttClient("ctrl:{seq}", connect=4, username='ctrl', password='ctrl')
        c    = MqttClient("client:{seq}", connect=4, username=user, password=password)

        ctrl.subscribe("test/#", qos=0)

        ## subscribe
        # MUST FAIL when acl on
        ret = c.subscribe("test/{0}/sub/0".format(client), qos=0)
        if not isinstance(ret, EventSuback):
            debug("{0}, acl {1}: {2}".format(client, acl, ret))
            return False
        if     acl and ret.granted_qos != [0x80] or\
           not acl and ret.granted_qos != [0]:
            debug("{0}, acl {1}: {2}".format(client, acl, ret))
            return False

        ## publish
        # NOTE: publish never reports failure or success
        topic = "test/{0}/pub/0".format(client); msg = env.gen_msg(10)
        c.publish(topic, msg)
        e = ctrl.recv()
        if acl and e != None:
            debug("{0}, acl {1}: {2}".format(client, acl, e))
            return False
        elif not acl and (not isinstance(e, EventPublish) or\
                e.msg.topic != topic or\
                e.msg.payload != msg):
            debug("{0}, acl {1}: {2}".format(client, acl, e))
            return False


        # MUST ALWAYS SUCCEED

        ret = c.subscribe("test/{0}/sub/1".format(client), qos=0)
        if not isinstance(ret, EventSuback) or ret.granted_qos != [0]:
            debug("{0}, acl {1}: {2}".format(client, acl, ret))
            return False

        if acl:
            ret = c.subscribe("test/{0}/sub/1/extra".format(client), qos=0)
            if not isinstance(ret, EventSuback) or ret.granted_qos != [0x80]:
                debug("{0}, acl {1}: {2}".format(client, acl, ret))
                return false

        topic = "test/{0}/pub/1".format(client); msg = env.gen_msg(10)
        c.publish(topic, msg)
        e = ctrl.recv()
        if not isinstance(e, EventPublish) or\
                e.msg.topic != topic or\
                e.msg.payload != msg:
            debug("{0}, acl {1}: {2}".format(client, acl, e))
            return False

        if acl:
            msg = env.gen_msg(10)
            c.publish("test/{0}/pub/1/extra".format(client), msg)
            e = ctrl.recv()
            if e != None:
                debug("{0}, acl {1}: {2}".format(client, acl, e))
                return False


        topic = "test/{0}/pub/2/foo/bar".format(client); msg = env.gen_msg(10)
        c.publish(topic, msg)
        e = ctrl.recv()
        if not isinstance(e, EventPublish) or\
                e.msg.topic != topic or\
                e.msg.payload != msg:
            debug("{0}, acl {1}: {2}".format(client, acl, e))
            return False

        ctrl.disconnect(); c.disconnect()
        return True

