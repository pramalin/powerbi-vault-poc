#!/usr/bin/env python3
"""Synchronize the Vault-managed reporting credential into a real Power BI
on-premises data gateway data source.

Commands
  login     Sign in with a device code (delegated mode) and cache the token.
  discover  List gateways and their data sources (IDs only, no secrets).
  sync      Read the Vault static credential, encrypt it with the gateway's
            public key and PATCH the gateway data source.
  status    Ask the gateway to test its connection to the database.
  refresh   Trigger a semantic-model refresh and wait for the result.

The credential is encrypted in this process with the gateway's RSA public key,
so neither the Power BI Service nor this script's logs ever see it in plain
text. The encryption helpers follow Microsoft's published Python sample:
https://github.com/microsoft/PowerBI-Developer-Samples/tree/master/Python/Encrypt%20credentials
"""
import argparse
import base64
import json
import os
import sys
import time

import msal
import requests
from cryptography.hazmat.primitives import hashes, hmac, padding as sym_padding
from cryptography.hazmat.primitives.asymmetric import padding, rsa
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes

API = os.environ.get("POWERBI_API_URL", "https://api.powerbi.com/v1.0/myorg")
AUTHORITY_HOST = os.environ.get("POWERBI_AUTHORITY_HOST", "https://login.microsoftonline.com")
RESOURCE = "https://analysis.windows.net/powerbi/api"
DELEGATED_SCOPES = [f"{RESOURCE}/Dataset.ReadWrite.All"]
TOKEN_CACHE = os.environ.get("POWERBI_TOKEN_CACHE", "/run/powerbi-auth/msal-cache.json")
TIMEOUT = 30


def env(name, required=True, default=None):
    value = os.environ.get(name, default)
    if required and not value:
        sys.exit(f"Missing {name}. Add it to .env (see .env.example).")
    return value


# --------------------------------------------------------------------------
# Gateway credential encryption (port of Microsoft's sample helpers)
# --------------------------------------------------------------------------
def _rsa_oaep(modulus, exponent, data):
    key = rsa.RSAPublicNumbers(int.from_bytes(exponent, "big"),
                               int.from_bytes(modulus, "big")).public_key()
    return key.encrypt(bytes(data), padding.OAEP(mgf=padding.MGF1(hashes.SHA256()),
                                                 algorithm=hashes.SHA256(), label=None))


def _authenticated_encrypt(key_enc, key_mac, message):
    """AES-256-CBC/PKCS7 then HMAC-SHA256: [alg ids(2)][mac(32)][iv(16)][ciphertext]."""
    algorithm_ids = bytes([0, 0])
    iv = os.urandom(16)
    padder = sym_padding.PKCS7(128).padder()
    padded = padder.update(message) + padder.finalize()
    encryptor = Cipher(algorithms.AES(key_enc), modes.CBC(iv)).encryptor()
    cipher_text = encryptor.update(padded) + encryptor.finalize()
    mac = hmac.HMAC(key_mac, hashes.SHA256())
    mac.update(algorithm_ids + iv + cipher_text)
    return algorithm_ids + mac.finalize() + iv + cipher_text


def encrypt_for_gateway(public_key, plain_text):
    modulus = base64.b64decode(public_key["modulus"])
    exponent = base64.b64decode(public_key["exponent"])
    data = plain_text.encode("utf-8")
    if len(modulus) == 128:  # legacy 1024-bit gateway key: chunked RSA-OAEP
        out = b"".join(_rsa_oaep(modulus, exponent, data[i:i + 60])
                       for i in range(0, len(data), 60))
        return base64.b64encode(out).decode()
    key_enc, key_mac = os.urandom(32), os.urandom(64)
    cipher_text = _authenticated_encrypt(key_enc, key_mac, data)
    wrapped_keys = _rsa_oaep(modulus, exponent, bytes([0, 1]) + key_enc + key_mac)
    return base64.b64encode(wrapped_keys).decode() + base64.b64encode(cipher_text).decode()


# --------------------------------------------------------------------------
# Microsoft Entra authentication
# --------------------------------------------------------------------------
def _load_cache():
    cache = msal.SerializableTokenCache()
    if os.path.exists(TOKEN_CACHE):
        with open(TOKEN_CACHE, encoding="utf-8") as handle:
            cache.deserialize(handle.read())
    return cache


def _save_cache(cache):
    if cache.has_state_changed:
        os.makedirs(os.path.dirname(TOKEN_CACHE), exist_ok=True)
        old_umask = os.umask(0o077)
        try:
            with open(TOKEN_CACHE, "w", encoding="utf-8") as handle:
                handle.write(cache.serialize())
        finally:
            os.umask(old_umask)


def access_token(interactive=False):
    tenant = env("POWERBI_TENANT_ID")
    client_id = env("POWERBI_CLIENT_ID")
    authority = f"{AUTHORITY_HOST}/{tenant}"
    mode = env("POWERBI_AUTH_MODE", default="device").lower()

    if mode == "service_principal":
        app = msal.ConfidentialClientApplication(
            client_id, authority=authority,
            client_credential=env("POWERBI_CLIENT_SECRET"))
        result = app.acquire_token_for_client(scopes=[f"{RESOURCE}/.default"])
    elif mode == "device":
        cache = _load_cache()
        app = msal.PublicClientApplication(client_id, authority=authority, token_cache=cache)
        accounts = app.get_accounts()
        result = app.acquire_token_silent(DELEGATED_SCOPES, account=accounts[0]) if accounts else None
        if not result:
            if not interactive:
                sys.exit("No cached Power BI sign-in. Run ./scripts/powerbi.sh login first.")
            flow = app.initiate_device_flow(scopes=DELEGATED_SCOPES)
            if "user_code" not in flow:
                sys.exit(f"Could not start device login: {flow.get('error_description', flow)}")
            print(flow["message"], flush=True)
            result = app.acquire_token_by_device_flow(flow)
        _save_cache(cache)
    else:
        sys.exit("POWERBI_AUTH_MODE must be 'device' or 'service_principal'.")

    if "access_token" not in result:
        sys.exit(f"Token request failed: {result.get('error')}: {result.get('error_description')}")
    return result["access_token"]


def api(method, path, token, **kwargs):
    response = requests.request(method, f"{API}{path}", timeout=TIMEOUT,
                                headers={"Authorization": f"Bearer {token}"}, **kwargs)
    return response


def fail_with(response, message):
    # Power BI error bodies contain codes, not credentials; safe to print.
    body = response.text[:2000] if response.text else ""
    sys.exit(f"{message} (HTTP {response.status_code}) {body}")


# --------------------------------------------------------------------------
# Vault
# --------------------------------------------------------------------------
def vault_credential():
    addr = env("VAULT_ADDR")
    role = env("VAULT_STATIC_ROLE", default="powerbi-reader")
    response = requests.get(f"{addr}/v1/database/static-creds/{role}", timeout=TIMEOUT,
                            headers={"X-Vault-Token": env("VAULT_TOKEN")})
    if response.status_code != 200:
        sys.exit(f"Vault read failed (HTTP {response.status_code}).")
    data = response.json()["data"]
    return data["username"], data["password"], data.get("last_vault_rotation")


# --------------------------------------------------------------------------
# Commands
# --------------------------------------------------------------------------
def cmd_login(_args):
    access_token(interactive=True)
    print("Power BI sign-in cached for later non-interactive runs.")


def cmd_discover(_args):
    token = access_token()
    gateways = api("GET", "/gateways", token)
    if gateways.status_code != 200:
        fail_with(gateways, "Could not list gateways")
    items = gateways.json().get("value", [])
    if not items:
        print("No gateways visible. Is this account an admin of the gateway?")
    for gateway in items:
        print(f"Gateway  {gateway['id']}  {gateway.get('name', '')}  ({gateway.get('type', '')})")
        sources = api("GET", f"/gateways/{gateway['id']}/datasources", token)
        if sources.status_code != 200:
            print(f"   (cannot list data sources: HTTP {sources.status_code})")
            continue
        for source in sources.json().get("value", []):
            print(f"   Data source  {source['id']}  {source.get('datasourceName', '')}  "
                  f"{source.get('datasourceType', '')}  {source.get('connectionDetails', '')}")
    print("\nCopy the IDs into POWERBI_GATEWAY_ID and POWERBI_DATASOURCE_ID in .env.")


def cmd_sync(_args):
    gateway_id = env("POWERBI_GATEWAY_ID")
    datasource_id = env("POWERBI_DATASOURCE_ID")
    username, password, rotated = vault_credential()
    token = access_token()

    gateway = api("GET", f"/gateways/{gateway_id}", token)
    if gateway.status_code != 200:
        fail_with(gateway, "Could not read gateway public key")

    plain = json.dumps({"credentialData": [{"name": "username", "value": username},
                                           {"name": "password", "value": password}]})
    body = {"credentialDetails": {
        "credentialType": "Basic",
        "credentials": encrypt_for_gateway(gateway.json()["publicKey"], plain),
        "encryptedConnection": env("POWERBI_ENCRYPTED_CONNECTION", default="NotEncrypted"),
        "encryptionAlgorithm": "RSA-OAEP",
        "privacyLevel": env("POWERBI_PRIVACY_LEVEL", default="Organizational"),
        "useEndUserOAuth2Credentials": False,
    }}
    del plain, password
    response = api("PATCH", f"/gateways/{gateway_id}/datasources/{datasource_id}", token, json=body)
    if response.status_code != 200:
        fail_with(response, "Gateway data source update failed")
    print(f"Gateway data source updated from Vault (Vault rotation time: {rotated}).")


def cmd_status(args):
    token = access_token()
    path = f"/gateways/{env('POWERBI_GATEWAY_ID')}/datasources/{env('POWERBI_DATASOURCE_ID')}/status"
    response = api("GET", path, token)
    if response.status_code == 200:
        print("Gateway connection test: OK")
        if args.expect_failure:
            sys.exit("Expected the stale credential to fail, but the gateway connected. "
                     "An existing database session may still be open.")
        return
    detail = ""
    try:
        detail = response.json().get("error", {}).get("code", "")
    except ValueError:
        pass
    print(f"Gateway connection test: FAILED (HTTP {response.status_code}) {detail}")
    sys.exit(0 if args.expect_failure else 1)


def cmd_refresh(_args):
    workspace = env("POWERBI_WORKSPACE_ID", required=False, default="me")
    dataset = env("POWERBI_DATASET_ID")
    token = access_token()
    # "My workspace" has no group ID; its datasets live directly under /datasets.
    scope = "" if workspace.lower() in ("", "me") else f"/groups/{workspace}"
    base = f"{scope}/datasets/{dataset}/refreshes"
    started = api("POST", base, token, json={"notifyOption": "NoNotification"})
    if started.status_code not in (200, 202):
        fail_with(started, "Could not start refresh")
    print("Refresh requested; waiting for completion...", flush=True)
    deadline = time.time() + int(env("POWERBI_REFRESH_TIMEOUT", default="600"))
    while time.time() < deadline:
        time.sleep(10)
        latest = api("GET", f"{base}?$top=1", token)
        if latest.status_code != 200:
            fail_with(latest, "Could not read refresh history")
        run = latest.json()["value"][0]
        if run["status"] == "Completed":
            print("Refresh completed.")
            return
        if run["status"] in ("Failed", "Disabled", "Cancelled"):
            error = run.get("serviceExceptionJson", "")
            sys.exit(f"Refresh {run['status']}: {error}")
    sys.exit("Timed out waiting for refresh.")


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("login").set_defaults(func=cmd_login)
    sub.add_parser("discover").set_defaults(func=cmd_discover)
    sub.add_parser("sync").set_defaults(func=cmd_sync)
    status = sub.add_parser("status")
    status.add_argument("--expect-failure", action="store_true",
                        help="exit 0 when the connection test fails (for the rotation demo)")
    status.set_defaults(func=cmd_status)
    sub.add_parser("refresh").set_defaults(func=cmd_refresh)
    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
