
import os
import os.path

for module in os.listdir(os.path.dirname(__file__)):
    if module.startswith('__') or not module.endswith('.py'): 
        continue

    __import__(module[:-3], locals(), globals())

