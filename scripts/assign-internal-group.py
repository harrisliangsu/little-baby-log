#!/usr/bin/env python3
"""Add the uploaded build to one existing internal TestFlight group.

Does not submit App Review, Beta App Review, or change testers.
"""

import base64
import json
import os
import subprocess
import time
import urllib.error
import urllib.request

GROUP = os.environ["GROUP_ID"]
BUNDLE = "com.harrisliangsu.littlebabylog"
API = "https://api.appstoreconnect.apple.com"


def b64(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode()


def der_to_raw(der: bytes) -> bytes:
    index = 2
    if der[index] != 0x02:
        raise SystemExit("ASC signature was not an ECDSA sequence")
    index += 1
    length = der[index]
    index += 1
    r = der[index : index + length]
    index += length
    if der[index] != 0x02:
        raise SystemExit("ASC signature was missing S")
    index += 1
    length = der[index]
    index += 1
    s = der[index : index + length]
    return r[-32:].rjust(32, b"\x00") + s[-32:].rjust(32, b"\x00")


def token() -> str:
    now = int(time.time())
    header = b64(json.dumps({"alg": "ES256", "kid": os.environ["KEY_ID"], "typ": "JWT"}, separators=(",", ":")).encode())
    payload = b64(
        json.dumps(
            {"iss": os.environ["ISSUER"], "iat": now, "exp": now + 900, "aud": "appstoreconnect-v1"},
            separators=(",", ":"),
        ).encode()
    )
    signing = f"{header}.{payload}".encode()
    der = subprocess.check_output(["openssl", "dgst", "-sha256", "-sign", os.environ["KEY_PATH"]], input=signing)
    return f"{header}.{payload}.{b64(der_to_raw(der))}"


def request(method: str, path: str, body=None, auth=None):
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(API + path, data=data, method=method)
    req.add_header("Authorization", "Bearer " + (auth or token()))
    req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=60) as response:
            raw = response.read()
            return response.status, json.loads(raw) if raw else {}
    except urllib.error.HTTPError as error:
        detail = error.read().decode("utf-8", "replace")[:500]
        raise SystemExit(f"ASC {method} {path} -> {error.code} {detail}") from None


def main():
    version = os.environ["BUILD"]
    marketing = os.environ["MARKETING_VERSION"]
    auth = token()
    _, apps = request("GET", f"/v1/apps?filter[bundleId]={BUNDLE}&limit=1", auth=auth)
    app_id = apps["data"][0]["id"]
    deadline = time.time() + 20 * 60
    build_id = None
    while time.time() < deadline:
        _, builds = request(
            "GET",
            f"/v1/builds?filter[app]={app_id}&filter[version]={version}&limit=5&include=preReleaseVersion",
            auth=auth,
        )
        for item in builds.get("data", []):
            if item["attributes"].get("version") == version:
                build_id = item["id"]
                break
        if build_id:
            break
        print(f"Build {marketing} ({version}) is not listed yet.")
        time.sleep(20)
        auth = token()
    if not build_id:
        raise SystemExit(f"Build {marketing} ({version}) did not appear in App Store Connect.")
    request(
        "POST",
        f"/v1/betaGroups/{GROUP}/relationships/builds",
        {"data": [{"type": "builds", "id": build_id}]},
        auth=auth,
    )
    deadline = time.time() + 20 * 60
    while time.time() < deadline:
        auth = token()
        listed = group_builds(auth)
        match = next((item for item in listed if item["id"] == build_id), None)
        if match is None:
            print(f"Build {build_id} is not on the internal group yet.")
            time.sleep(20)
            continue
        state = match["attributes"].get("processingState", "")
        marketing_version = pre_release_version(build_id, auth)
        if marketing_version != marketing:
            raise SystemExit(f"Build {build_id} is {marketing_version}, not {marketing}.")
        if state == "VALID" and match["attributes"].get("expired") is not True:
            print(f"Build {marketing} ({version}) {build_id} is in internal group {GROUP} and available.")
            return
        print(f"Build {build_id} processingState={state}.")
        time.sleep(20)
    raise SystemExit(f"Build {build_id} was not available in the internal group.")


def group_builds(auth: str) -> list:
    path = f"/v1/betaGroups/{GROUP}/builds?limit=50"
    rows = []
    while path:
        _, page = request("GET", path, auth=auth)
        rows.extend(page.get("data", []))
        nxt = page.get("links", {}).get("next")
        if isinstance(nxt, str) and nxt.startswith(API):
            path = nxt[len(API):]
        else:
            path = None
    return rows


def pre_release_version(build_id: str, auth: str) -> str:
    _, payload = request("GET", f"/v1/builds/{build_id}/preReleaseVersion", auth=auth)
    return payload.get("data", {}).get("attributes", {}).get("version", "")


if __name__ == "__main__":
    main()
