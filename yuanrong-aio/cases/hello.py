#!/usr/bin/env python3
# Minimal openYuanRong case: import yr, init against the local AIO cluster,
# run one stateless invoke. Run inside an AIO container:
#   YR_SMOKE_SERVER_ADDRESS=127.0.0.1:8888 python3 hello.py
import os
import yr
from yr.config import Config

addr = os.environ.get("YR_SMOKE_SERVER_ADDRESS", "127.0.0.1:8888")
conf = Config(server_address=addr, is_driver=True, auto=False)
conf.in_cluster = False
yr.init(conf)
print("yr.init OK against", addr)


@yr.invoke
def add_one(x):
    return x + 1


print("add_one(41) =", yr.get(add_one.invoke(41)))
yr.finalize()
print("done")
