import asyncio
import json
import os
import time

import aiohttp
import boto3

REGION_AUTH = os.environ.get("AUTH_REGION", "us-east-1")
COGNITO_CLIENT_ID = os.environ["COGNITO_CLIENT_ID"]
USERNAME = os.environ["COGNITO_USERNAME"]          # your email
PASSWORD = os.environ["COGNITO_PASSWORD"]          # same as terraform var
API_R1 = os.environ["API_R1_BASE_URL"].rstrip("/")
API_R2 = os.environ["API_R2_BASE_URL"].rstrip("/")

EXPECTED_R1 = os.environ.get("EXPECTED_REGION_1", "us-east-1")
EXPECTED_R2 = os.environ.get("EXPECTED_REGION_2", "eu-west-1")

def get_jwt():
    idp = boto3.client("cognito-idp", region_name=REGION_AUTH)
    resp = idp.initiate_auth(
        ClientId=COGNITO_CLIENT_ID,
        AuthFlow="USER_PASSWORD_AUTH",
        AuthParameters={"USERNAME": USERNAME, "PASSWORD": PASSWORD},
    )
    return resp["AuthenticationResult"]["IdToken"]

async def call_api(session, method, url, token, expected_region):
    headers = {"Authorization": f"Bearer {token}"}
    t0 = time.perf_counter()
    async with session.request(method, url, headers=headers) as r:
        text = await r.text()
        dt_ms = (time.perf_counter() - t0) * 1000.0

        try:
            data = json.loads(text)
        except Exception:
            data = {"raw": text}

        region = data.get("region")
        ok = (region == expected_region)

        return {
            "url": url,
            "status": r.status,
            "latency_ms": round(dt_ms, 2),
            "response": data,
            "assert_region_ok": ok,
            "region_returned": region,
            "region_expected": expected_region,
        }

async def main():
    token = get_jwt()
    async with aiohttp.ClientSession() as session:
        tasks = [
            call_api(session, "GET",  f"{API_R1}/greet",    token, EXPECTED_R1),
            call_api(session, "GET",  f"{API_R2}/greet",    token, EXPECTED_R2),
            call_api(session, "POST", f"{API_R1}/dispatch", token, EXPECTED_R1),
            call_api(session, "POST", f"{API_R2}/dispatch", token, EXPECTED_R2),
        ]
        results = await asyncio.gather(*tasks)

    for r in results:
        print("\n---")
        print(f"URL: {r['url']}")
        print(f"HTTP: {r['status']}")
        print(f"Latency: {r['latency_ms']} ms")
        print(f"Region: {r['region_returned']} (expected {r['region_expected']})")
        print(f"Assert region match: {r['assert_region_ok']}")
        print("Response:", json.dumps(r["response"], indent=2))

    # Hard fail if any assertion fails
    failed = [x for x in results if not x["assert_region_ok"] or x["status"] != 200]
    if failed:
        raise SystemExit(f"\nFAILED: {len(failed)} calls did not meet assertions.")
    print("\nALL PASSED ✅")

if __name__ == "__main__":
    asyncio.run(main())