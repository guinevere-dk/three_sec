#!/usr/bin/env python3
"""Upload an Android App Bundle to Google Play with service-account auth only.

Examples:
  python tools/google_play_release.py --track internal --validate-only
  python tools/google_play_release.py --track production --rollout 0.05 --confirm-production --validate-only
  python tools/google_play_release.py --track production --rollout 0.05 --confirm-production
  python tools/google_play_release.py --track production --rollout 1 --confirm-production --confirm-full-production
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path
from typing import Any

import httplib2
from google_auth_httplib2 import AuthorizedHttp
from google.oauth2 import service_account
from googleapiclient.discovery import build
from googleapiclient.errors import HttpError


PACKAGE_NAME = "com.dk.three_sec"
EXPECTED_SERVICE_ACCOUNT = (
    "moa-play-release-bot@fir-3s-8edb9.iam.gserviceaccount.com"
)
ANDROID_PUBLISHER_SCOPE = "https://www.googleapis.com/auth/androidpublisher"
DEFAULT_AAB = Path("build/app/outputs/bundle/release/app-release.aab")
DEFAULT_MAPPING = Path("build/app/outputs/mapping/release/mapping.txt")
HTTP_TIMEOUT_SECONDS = 300
LOCAL_SERVICE_ACCOUNT_CANDIDATES = (
    Path(r"C:\Users\Guiny\Documents\Python_Project\secrets\ fir-3s-8edb9-06e4953d6e02.json"),
    Path(r"C:\Users\Guiny\Documents\Python_Project\secrets\fir-3s-8edb9-06e4953d6e02.json"),
)


class ReleaseError(RuntimeError):
    pass


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Create a Google Play edit and upload a MOA Android release."
    )
    parser.add_argument("--package-name", default=PACKAGE_NAME)
    parser.add_argument("--track", choices=("internal", "production"), required=True)
    parser.add_argument("--rollout", type=float, default=0.05)
    parser.add_argument("--aab", type=Path, default=DEFAULT_AAB)
    parser.add_argument("--mapping", type=Path, default=DEFAULT_MAPPING)
    parser.add_argument("--skip-mapping", action="store_true")
    parser.add_argument("--release-notes-dir", type=Path)
    parser.add_argument("--version", help="Expected pubspec version, for example 2.1.5+215")
    parser.add_argument("--release-name")
    parser.add_argument("--validate-only", action="store_true")
    parser.add_argument("--confirm-production", action="store_true")
    parser.add_argument("--confirm-full-production", action="store_true")
    return parser.parse_args()


def repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def read_pubspec_version(root: Path) -> tuple[str, int]:
    pubspec = root / "pubspec.yaml"
    match = re.search(r"^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)\s*$", pubspec.read_text(encoding="utf-8"), re.M)
    if not match:
        raise ReleaseError("Could not parse pubspec.yaml version.")
    return match.group(1), int(match.group(2))


def resolve_path(root: Path, path: Path) -> Path:
    return path if path.is_absolute() else root / path


def service_account_path() -> Path:
    env_path = os.environ.get("GOOGLE_PLAY_SERVICE_ACCOUNT_JSON")
    if env_path:
        candidate = Path(env_path)
        if candidate.is_file():
            return candidate
        raise ReleaseError("GOOGLE_PLAY_SERVICE_ACCOUNT_JSON is set but the file does not exist.")

    for candidate in LOCAL_SERVICE_ACCOUNT_CANDIDATES:
        if candidate.is_file():
            return candidate

    raise ReleaseError(
        "No Google Play service account JSON found. Set GOOGLE_PLAY_SERVICE_ACCOUNT_JSON "
        "or place the ignored local service account file in the configured secrets directory."
    )


def load_credentials() -> service_account.Credentials:
    path = service_account_path()
    with path.open("r", encoding="utf-8") as handle:
        data = json.load(handle)
    client_email = data.get("client_email")
    if client_email != EXPECTED_SERVICE_ACCOUNT:
        raise ReleaseError(
            "Service account JSON client_email does not match the expected MOA Play release bot."
        )
    return service_account.Credentials.from_service_account_file(
        str(path), scopes=[ANDROID_PUBLISHER_SCOPE]
    )


def read_release_notes(notes_dir: Path) -> list[dict[str, str]]:
    if not notes_dir.is_dir():
        raise ReleaseError(f"Release notes directory does not exist: {notes_dir}")
    notes: list[dict[str, str]] = []
    for note_file in sorted(notes_dir.glob("*.txt")):
        language = note_file.stem
        text = note_file.read_text(encoding="utf-8").strip()
        if not text:
            raise ReleaseError(f"Release notes file is empty: {note_file}")
        notes.append({"language": language, "text": text})
    if not notes:
        raise ReleaseError(f"No release note .txt files found in: {notes_dir}")
    return notes


def validate_inputs(args: argparse.Namespace, root: Path) -> dict[str, Any]:
    version_name, version_code = read_pubspec_version(root)
    expected_version = args.version or f"{version_name}+{version_code}"
    if expected_version != f"{version_name}+{version_code}":
        raise ReleaseError(
            f"Expected version {expected_version}, but pubspec.yaml has {version_name}+{version_code}."
        )

    if args.package_name != PACKAGE_NAME:
        raise ReleaseError(f"Package name must remain {PACKAGE_NAME}.")

    if args.track == "production":
        if not args.confirm_production:
            raise ReleaseError("Production uploads require --confirm-production.")
        if not (0.0 < args.rollout <= 1.0):
            raise ReleaseError("Production rollout must use 0.0 < --rollout <= 1.0.")
        if args.rollout >= 1.0 and not args.confirm_full_production:
            raise ReleaseError(
                "100% production releases require --confirm-full-production."
            )

    aab = resolve_path(root, args.aab)
    if not aab.is_file():
        raise ReleaseError(f"AAB not found: {aab}")

    notes_dir = resolve_path(
        root,
        args.release_notes_dir or Path("release/google_play") / version_name,
    )
    release_notes = read_release_notes(notes_dir)

    mapping = resolve_path(root, args.mapping)
    upload_mapping = not args.skip_mapping and mapping.is_file()

    return {
        "version_name": version_name,
        "version_code": version_code,
        "aab": aab,
        "mapping": mapping,
        "upload_mapping": upload_mapping,
        "release_notes": release_notes,
        "release_name": args.release_name or f"MOA {version_name} ({version_code})",
    }


def upload_mapping_file(service: Any, package_name: str, edit_id: str, version_code: int, mapping: Path) -> None:
    service.edits().deobfuscationfiles().upload(
        packageName=package_name,
        editId=edit_id,
        apkVersionCode=version_code,
        deobfuscationFileType="proguard",
        media_body=str(mapping),
        media_mime_type="application/octet-stream",
    ).execute()


def run() -> int:
    args = parse_args()
    root = repo_root()

    try:
        release = validate_inputs(args, root)
        credentials = load_credentials()
        authorized_http = AuthorizedHttp(
            credentials,
            http=httplib2.Http(timeout=HTTP_TIMEOUT_SECONDS),
        )
        service = build(
            "androidpublisher",
            "v3",
            http=authorized_http,
            cache_discovery=False,
        )

        edit = service.edits().insert(packageName=args.package_name, body={}).execute()
        edit_id = edit["id"]
        committed = False

        try:
            bundle = service.edits().bundles().upload(
                packageName=args.package_name,
                editId=edit_id,
                media_body=str(release["aab"]),
                media_mime_type="application/octet-stream",
            ).execute()
            uploaded_version_code = int(bundle["versionCode"])
            if uploaded_version_code != release["version_code"]:
                raise ReleaseError(
                    f"Uploaded AAB versionCode {uploaded_version_code} did not match "
                    f"pubspec versionCode {release['version_code']}."
                )

            if release["upload_mapping"]:
                upload_mapping_file(
                    service,
                    args.package_name,
                    edit_id,
                    uploaded_version_code,
                    release["mapping"],
                )

            status = "completed"
            track_release: dict[str, Any] = {
                "name": release["release_name"],
                "versionCodes": [str(uploaded_version_code)],
                "status": status,
                "releaseNotes": release["release_notes"],
            }
            if args.track == "production":
                if args.rollout < 1.0:
                    track_release["status"] = "inProgress"
                    track_release["userFraction"] = args.rollout

            track_result = service.edits().tracks().update(
                packageName=args.package_name,
                editId=edit_id,
                track=args.track,
                body={"track": args.track, "releases": [track_release]},
            ).execute()

            if args.validate_only:
                validation = service.edits().validate(
                    packageName=args.package_name, editId=edit_id
                ).execute()
                print(json.dumps({
                    "mode": "validate-only",
                    "packageName": args.package_name,
                    "track": args.track,
                    "rollout": args.rollout if args.track == "production" else None,
                    "versionName": release["version_name"],
                    "versionCode": uploaded_version_code,
                    "trackResult": track_result,
                    "validation": validation,
                }, ensure_ascii=False, indent=2))
            else:
                commit = service.edits().commit(
                    packageName=args.package_name, editId=edit_id
                ).execute()
                committed = True
                print(json.dumps({
                    "mode": "commit",
                    "packageName": args.package_name,
                    "track": args.track,
                    "rollout": args.rollout if args.track == "production" else None,
                    "versionName": release["version_name"],
                    "versionCode": uploaded_version_code,
                    "trackResult": track_result,
                    "commit": commit,
                }, ensure_ascii=False, indent=2))
        except Exception:
            if not committed:
                try:
                    service.edits().delete(packageName=args.package_name, editId=edit_id).execute()
                except Exception:
                    pass
            raise
    except (HttpError, ReleaseError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(run())
