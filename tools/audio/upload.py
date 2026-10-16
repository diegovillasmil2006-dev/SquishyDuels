"""Uploads audio files to the DIJAY Studios group through Roblox Open Cloud (Assets API v1).

usage: python -I upload.py <file> <displayName> <description>
The API key comes from the ROBLOX_API_KEY environment variable (never printed). Prints the operation result JSON.
"""

import json
import os
import sys
import time
import urllib.request
import uuid

GROUP_ID = "706867720"
API = "https://apis.roblox.com/assets/v1"


def request(url, data=None, headers=None, method=None):
    req = urllib.request.Request(url, data=data, headers=headers or {}, method=method)
    req.add_header("x-api-key", os.environ["ROBLOX_API_KEY"])
    try:
        with urllib.request.urlopen(req, timeout=120) as res:
            return json.loads(res.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        return {"httpError": e.code, "body": e.read().decode("utf-8", "replace")}


def upload(path, name, description):
    meta = {
        "assetType": "Audio",
        "displayName": name,
        "description": description,
        "creationContext": {"creator": {"groupId": GROUP_ID}},
    }
    boundary = uuid.uuid4().hex
    body = b""
    body += f"--{boundary}\r\nContent-Disposition: form-data; name=\"request\"\r\nContent-Type: application/json\r\n\r\n".encode()
    body += json.dumps(meta).encode() + b"\r\n"
    fname = os.path.basename(path)
    body += f"--{boundary}\r\nContent-Disposition: form-data; name=\"fileContent\"; filename=\"{fname}\"\r\nContent-Type: audio/ogg\r\n\r\n".encode()
    body += open(path, "rb").read() + b"\r\n"
    body += f"--{boundary}--\r\n".encode()
    op = request(f"{API}/assets", body, {"Content-Type": f"multipart/form-data; boundary={boundary}"}, "POST")
    if "path" not in op:
        return op
    for _ in range(40):
        res = request(f"{API}/{op['path']}")
        if res.get("done"):
            return res
        time.sleep(3)
    return {"timeout": op}


if __name__ == "__main__":
    print(json.dumps(upload(sys.argv[1], sys.argv[2], sys.argv[3]), indent=1))
