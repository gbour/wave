
local redis  = require "redis"
local client = redis.connect("127.0.0.1", 6379)
print("client=",client)
local resp   = client:ping()
print("ping=", ping)
print("foo=", client:get("foo"))

--
client:hmset("u:1", {userid= "1", username= "system", password= "password"})

client:hmset("u:14307", {userid= "14307", username= "jdoe"  , password= "password"})
client:hmset("u:95847", {userid= "95847", username= "anonym", password= "password"})

client:set("key:user/userid/jdoe"   , "14307")
client:set("key:user/userid/aneonym", "95847")


client:hmset("device:1/1", {userid= "1", deviceid="wavectl/0.1", username= "wavectl", password= "password"})

client:hmset("device:14307/shamallow.1", {userid= 14307, deviceid= "jdoe/shamallow.1", username= "sham", password= "allow"})
client:hmset("device:14308/therm", {userid= 14307, deviceid= "jdoe/therm", username= "xyz", password= "yuv"})

client:set("key:device/deviceid/wavectl/0.1"     , "device:1/1")
client:set("key:device/deviceid/jdoe/shamallow.1", "device:14307/shamallow.1")
client:set("key:device/deviceid/jdoe/therm"      , "device:14308/therm")

client:del("set:user/devices/u:14307")
client:sadd("set:user/devices/u:14307", "device:14307/shamallow.1", "device:14308/therm")

