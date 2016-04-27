
import time
from mosquitto import *

def on_connect(m, userdata, rc):
    print("connect: {0}".format(rc))

def on_log(m, userdata, level, buf):
    print("log: {0} {1} {2}".format(userdata,level,buf))

m=Mosquitto('plop')

m.connect('localhost',4949, 2)
m.on_log = on_log
m.on_connect = on_connect

for i in range(10):
    print("loop", i)
    #time.sleep(1)
    m.loop()

print("disconnection")
m.disconnect()

