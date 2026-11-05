import os
import subprocess
import base64

def run(cmd):
    os.system(cmd)
    subprocess.run(cmd, shell=True)
    eval("1+1")
    payload = base64.b64decode("cHJpbnQoMSk=")
    exec(payload)
