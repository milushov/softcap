#!/usr/bin/env python3
"""Sends store/metadata (and the screenshots) to App Store Connect.

    ASC_KEY_ID=… ASC_ISSUER_ID=… ASC_KEY_PATH=/path/AuthKey_….p8 \
        python3 tools/push_store_metadata.py --version 0.1.28 [--screenshots DIR]

What goes where, because App Store Connect splits the listing in two and the
halves behave differently:

  The name and the subtitle belong to the *app*, through an `appInfo`. There
  are two of those once a version is in preparation — one describing what is on
  sale, which is read-only, and one describing what is being prepared. Writing
  to the wrong one is refused, so this finds the editable one by its state.

  The description, keywords, promotional text and release notes belong to the
  *version*. A version that is on sale has none that can be edited either,
  which is why `--version` exists: it creates the next one if it is not there,
  and that is the only thing here that changes what Apple will review.

Nothing is submitted for review. This writes the listing and stops; a person
presses the button.

The three ASC_ variables are read from the environment and never written down:
they name an Apple account, and this repository publishes everything in it.
"""

import argparse
import base64
import hashlib
import json
import os
import pathlib
import subprocess
import sys
import time
import urllib.error
import urllib.request

HERE = pathlib.Path(__file__).resolve().parent.parent
BUNDLE_ID = "app.softcap.Softcap"
BASE = "https://api.appstoreconnect.apple.com"
FIELDS = ["name", "subtitle", "keywords", "description", "promotional_text", "whats_new"]

# The App Store Connect names for what the app calls a version localisation.
VERSION_FIELDS = {"description": "description", "keywords": "keywords",
                  "promotional_text": "promotionalText", "whats_new": "whatsNew"}
INFO_FIELDS = {"name": "name", "subtitle": "subtitle"}

# The three links Apple shows beside the listing, in the reader's language: the
# site is the same ten languages, and a Russian listing whose "App Support"
# button opens an English page is a localisation that stops at the border. The
# path is the site's own — `site/ru/support/`, `site/zh-hans/privacy/` — and
# `TheListingLinksIntoTheRightLanguage` checks these against the pages that
# exist rather than trusting the spelling here.
SITE_LANGUAGE = {
    "en-US": "", "ru": "ru/", "es-ES": "es/", "es-MX": "es/", "fr-FR": "fr/",
    "pt-BR": "pt-br/", "hi": "hi/", "id": "id/", "ar-SA": "ar/", "zh-Hans": "zh-hans/",
}


def links(locale: str) -> dict:
    if locale not in SITE_LANGUAGE:
        raise SystemExit(f"{locale} has a listing but no entry in SITE_LANGUAGE — "
                         "which page should its three links open?")
    prefix = f"https://softcap.app/{SITE_LANGUAGE[locale]}"
    return {"marketingUrl": prefix,
            "supportUrl": f"{prefix}support/",
            "privacyPolicyUrl": f"{prefix}privacy/"}


# MARK: - the key


def token() -> str:
    """A ten-minute ES256 assertion, signed by openssl — a runner has no pyjwt."""
    key_id = os.environ["ASC_KEY_ID"].strip()
    issuer = os.environ["ASC_ISSUER_ID"].strip()
    path = os.environ["ASC_KEY_PATH"].strip()

    def segment(data: bytes) -> str:
        return base64.urlsafe_b64encode(data).rstrip(b"=").decode()

    now = int(time.time())
    header = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
    claims = {"iss": issuer, "iat": now, "exp": now + 600, "aud": "appstoreconnect-v1"}
    signing_input = f"{segment(json.dumps(header).encode())}.{segment(json.dumps(claims).encode())}"
    signed = subprocess.run(["openssl", "dgst", "-sha256", "-sign", path],
                            input=signing_input.encode(), capture_output=True, check=True)
    # openssl writes ECDSA-Sig-Value ::= SEQUENCE { r INTEGER, s INTEGER }; a JWT
    # wants the two numbers side by side, 32 bytes each.
    der = signed.stdout
    index = 2 if der[1] < 0x80 else 3 + (der[1] & 0x7F) - 1

    def integer(at: int) -> tuple[bytes, int]:
        length = der[at + 1]
        return der[at + 2:at + 2 + length].lstrip(b"\x00").rjust(32, b"\x00"), at + 2 + length

    r, index = integer(index)
    s, _ = integer(index)
    return f"{signing_input}.{segment(r + s)}"


def call(method: str, path: str, body=None, raw: bytes | None = None, headers=None):
    url = path if path.startswith("http") else BASE + path
    data = raw if raw is not None else (json.dumps(body).encode() if body is not None else None)
    request = urllib.request.Request(url, data=data, method=method)
    if raw is None:
        request.add_header("Authorization", f"Bearer {token()}")
        if data:
            request.add_header("Content-Type", "application/json")
    for name, value in (headers or {}).items():
        request.add_header(name, value)
    try:
        with urllib.request.urlopen(request, timeout=120) as response:
            payload = response.read()
            return json.loads(payload) if payload and response.headers.get(
                "Content-Type", "").startswith("application/") else {}
    except urllib.error.HTTPError as error:
        detail = error.read().decode()
        raise SystemExit(f"{method} {url} -> {error.code}\n{detail[:1500]}")


# MARK: - what to write into


def app_id() -> str:
    found = call("GET", f"/v1/apps?filter[bundleId]={BUNDLE_ID}&fields[apps]=name")
    if not found["data"]:
        raise SystemExit(f"no app with bundle id {BUNDLE_ID} on this account")
    return found["data"][0]["id"]


# The states in which App Store Connect lets the text be changed. Anything else
# is either finished with — on sale, replaced, taken down — or locked while
# Apple looks at it, and writing into a locked version is refused one field at a
# time with a 409 that does not say why.
EDITABLE = {"PREPARE_FOR_SUBMISSION", "READY_FOR_REVIEW", "DEVELOPER_REJECTED",
            "REJECTED", "METADATA_REJECTED", "INVALID_BINARY",
            "WAITING_FOR_EXPORT_COMPLIANCE"}
FINISHED = {"READY_FOR_SALE", "REPLACED_WITH_NEW_VERSION", "REMOVED_FROM_SALE",
            "DEVELOPER_REMOVED_FROM_SALE"}


def editable_version(app: str, want: str | None) -> str:
    """The version being prepared, created if `want` names one that is not there."""
    versions = call("GET", f"/v1/apps/{app}/appStoreVersions?limit=20"
                           "&fields[appStoreVersions]=versionString,appStoreState")
    for version in versions["data"]:
        number = version["attributes"]["versionString"]
        state = version["attributes"]["appStoreState"]
        if state in EDITABLE:
            print(f"editing version {number} ({state})")
            return version["id"]
        if state not in FINISHED:
            raise SystemExit(f"version {number} is {state}: Apple has it, and its text is "
                             "locked until review ends or it is pulled from review")
    if not want:
        raise SystemExit("every version is on sale and --version did not name a new one")
    made = call("POST", "/v1/appStoreVersions", {"data": {
        "type": "appStoreVersions",
        "attributes": {"platform": "MAC_OS", "versionString": want},
        "relationships": {"app": {"data": {"type": "apps", "id": app}}},
    }})
    print(f"created version {want}")
    return made["data"]["id"]


def editable_info(app: str) -> str:
    """The `appInfo` that is not the one describing what is on sale."""
    infos = call("GET", f"/v1/apps/{app}/appInfos")
    for info in infos["data"]:
        if info["attributes"].get("appStoreState") in EDITABLE:
            return info["id"]
    raise SystemExit("no editable appInfo — is there a version in preparation?")


# MARK: - the build


def attach_latest_build(app: str, version: str) -> None:
    """Hangs the newest usable build on the version, and agrees on the number.

    Apple refuses a version whose string is not the build's own
    `CFBundleShortVersionString`, and the release workflow uploads a build per
    push — so the number that was right when this version record was made is
    usually not the number of the build that should go on it. The build is
    chosen first and the record renamed to match, rather than the other way
    round.
    """
    builds = call("GET", f"/v1/builds?filter[app]={app}&limit=10&sort=-uploadedDate"
                         "&include=preReleaseVersion")
    marketing = {row["id"]: row["attributes"]["version"]
                 for row in builds.get("included", [])
                 if row["type"] == "preReleaseVersions"}
    for build in builds["data"]:
        attributes = build["attributes"]
        if attributes.get("processingState") != "VALID" or attributes.get("expired"):
            continue
        pre = build["relationships"]["preReleaseVersion"]["data"]["id"]
        number = marketing.get(pre)
        call("PATCH", f"/v1/appStoreVersions/{version}", {"data": {
            "type": "appStoreVersions", "id": version,
            "attributes": {"versionString": number},
        }})
        call("PATCH", f"/v1/appStoreVersions/{version}/relationships/build",
             {"data": {"type": "builds", "id": build["id"]}})
        print(f"attached build {attributes['version']} of {number}")
        return
    raise SystemExit("no build has finished processing yet")


# MARK: - the text


def read(locale: pathlib.Path) -> dict:
    out = {}
    for field in FIELDS:
        path = locale / f"{field}.txt"
        if path.exists():
            out[field] = path.read_text(encoding="utf-8").strip()
    return out


def push_text(info: str, version: str, only: set[str] | None) -> None:
    info_locales = {row["attributes"]["locale"]: row["id"] for row in
                    call("GET", f"/v1/appInfos/{info}/appInfoLocalizations")["data"]}
    version_locales = {row["attributes"]["locale"]: row["id"] for row in
                       call("GET", f"/v1/appStoreVersions/{version}/appStoreVersionLocalizations")["data"]}

    for directory in sorted((HERE / "store/metadata").iterdir()):
        if not directory.is_dir() or (only and directory.name not in only):
            continue
        locale = directory.name
        text = read(directory)

        attributes = {key: text[field] for field, key in INFO_FIELDS.items() if field in text}
        attributes["privacyPolicyUrl"] = links(locale)["privacyPolicyUrl"]
        if locale in info_locales:
            call("PATCH", f"/v1/appInfoLocalizations/{info_locales[locale]}",
                 {"data": {"type": "appInfoLocalizations", "id": info_locales[locale],
                           "attributes": attributes}})
        else:
            call("POST", "/v1/appInfoLocalizations", {"data": {
                "type": "appInfoLocalizations",
                "attributes": {"locale": locale, **attributes},
                "relationships": {"appInfo": {"data": {"type": "appInfos", "id": info}}},
            }})
            # Adding a language to the app adds it to the version as well, on
            # Apple's side and without saying so. Asking again is what stops the
            # next call creating a second one and being refused for it.
            version_locales = {row["attributes"]["locale"]: row["id"] for row in
                               call("GET", f"/v1/appStoreVersions/{version}"
                                           "/appStoreVersionLocalizations")["data"]}

        attributes = {key: text[field] for field, key in VERSION_FIELDS.items() if field in text}
        page = links(locale)
        attributes["marketingUrl"] = page["marketingUrl"]
        attributes["supportUrl"] = page["supportUrl"]
        if locale in version_locales:
            call("PATCH", f"/v1/appStoreVersionLocalizations/{version_locales[locale]}",
                 {"data": {"type": "appStoreVersionLocalizations",
                           "id": version_locales[locale], "attributes": attributes}})
        else:
            made = call("POST", "/v1/appStoreVersionLocalizations", {"data": {
                "type": "appStoreVersionLocalizations",
                "attributes": {"locale": locale, **attributes},
                "relationships": {"appStoreVersion": {
                    "data": {"type": "appStoreVersions", "id": version}}},
            }})
            version_locales[locale] = made["data"]["id"]
        print(f"  {locale}: text written")


# MARK: - the pictures


def push_screenshots(version: str, source: pathlib.Path, only: set[str] | None) -> None:
    version_locales = {row["attributes"]["locale"]: row["id"] for row in
                       call("GET", f"/v1/appStoreVersions/{version}/appStoreVersionLocalizations")["data"]}

    for directory in sorted(source.iterdir()):
        if not directory.is_dir() or directory.name.startswith(".") or (
                only and directory.name not in only):
            continue
        locale = directory.name
        if locale not in version_locales:
            print(f"  {locale}: no localisation to hang screenshots on — skipped")
            continue
        pictures = sorted(directory.glob("*.png"))
        if not pictures:
            continue

        # One set per locale, emptied rather than added to: a second run would
        # otherwise leave ten screenshots where the store shows the first few.
        sets = call("GET", f"/v1/appStoreVersionLocalizations/{version_locales[locale]}"
                           "/appScreenshotSets")
        target = next((row["id"] for row in sets["data"]
                       if row["attributes"]["screenshotDisplayType"] == "APP_DESKTOP"), None)
        if target:
            for old in call("GET", f"/v1/appScreenshotSets/{target}/appScreenshots")["data"]:
                call("DELETE", f"/v1/appScreenshots/{old['id']}")
        else:
            target = call("POST", "/v1/appScreenshotSets", {"data": {
                "type": "appScreenshotSets",
                "attributes": {"screenshotDisplayType": "APP_DESKTOP"},
                "relationships": {"appStoreVersionLocalization": {"data": {
                    "type": "appStoreVersionLocalizations", "id": version_locales[locale]}}},
            }})["data"]["id"]

        uploaded = []
        for picture in pictures:
            uploaded.append(upload(picture, target))
        # The store shows them in the order of the relationship, not the order
        # they were sent; the numbers in the file names are the intended one.
        call("PATCH", f"/v1/appScreenshotSets/{target}/relationships/appScreenshots",
             {"data": [{"type": "appScreenshots", "id": identifier} for identifier in uploaded]})
        print(f"  {locale}: {len(uploaded)} screenshots")


def upload(picture: pathlib.Path, into: str) -> str:
    """Reserves a screenshot, sends the bytes where Apple says, and commits it."""
    payload = picture.read_bytes()
    reservation = call("POST", "/v1/appScreenshots", {"data": {
        "type": "appScreenshots",
        "attributes": {"fileSize": len(payload), "fileName": picture.name},
        "relationships": {"appScreenshotSet": {
            "data": {"type": "appScreenshotSets", "id": into}}},
    }})
    identifier = reservation["data"]["id"]
    for operation in reservation["data"]["attributes"]["uploadOperations"]:
        headers = {header["name"]: header["value"] for header in operation["requestHeaders"]}
        chunk = payload[operation["offset"]:operation["offset"] + operation["length"]]
        call(operation["method"], operation["url"], raw=chunk, headers=headers)
    call("PATCH", f"/v1/appScreenshots/{identifier}", {"data": {
        "type": "appScreenshots", "id": identifier,
        "attributes": {"uploaded": True,
                       "sourceFileChecksum": hashlib.md5(payload).hexdigest()},
    }})
    return identifier


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", help="create this version if none is in preparation")
    parser.add_argument("--screenshots", type=pathlib.Path,
                        help="a directory of <locale>/*.png, as tools/store_screenshots.py writes")
    parser.add_argument("--locales", help="comma-separated, for trying one before all ten")
    parser.add_argument("--text", action="store_true", help="write the text only")
    parser.add_argument("--build", action="store_true",
                        help="attach the newest processed build, and take its version number")
    arguments = parser.parse_args()

    for name in ("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_KEY_PATH"):
        if not os.environ.get(name):
            print(f"{name} is not set; see the docstring", file=sys.stderr)
            return 1

    only = set(arguments.locales.split(",")) if arguments.locales else None
    app = app_id()
    version = editable_version(app, arguments.version)
    if arguments.build:
        attach_latest_build(app, version)
    push_text(editable_info(app), version, only)
    if arguments.screenshots and not arguments.text:
        push_screenshots(version, arguments.screenshots, only)
    print("written. Nothing was submitted for review.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
