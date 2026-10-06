"""Build released CIPP source with a small, validated Prometheus overlay."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import urllib.request

ROOT = Path(__file__).resolve().parent
STANDARD = "PrometheusTeamsExternalChatFiles"
FUNCTION = f"Invoke-CIPPStandard{STANDARD}"
SOURCE_FILE = f"{FUNCTION}.ps1"


def api(path):
    headers = {"Accept": "application/vnd.github+json", "User-Agent": "Prometheus-CIPP-build"}
    if os.environ.get("GH_TOKEN"):
        headers["Authorization"] = f"Bearer {os.environ['GH_TOKEN']}"
    request = urllib.request.Request(f"https://api.github.com{path}", headers=headers)
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


def overlay_hash():
    digest = hashlib.sha256()
    files = [p for p in ROOT.rglob("*") if p.is_file() and
             p.name != "build-state.json" and "__pycache__" not in p.parts]
    files.append(ROOT.parent / ".github/workflows/prometheus-container.yml")
    for path in sorted(files):
        digest.update(path.relative_to(ROOT.parent).as_posix().encode())
        digest.update(b"\0")
        digest.update(path.read_bytes().replace(b"\r\n", b"\n"))
        digest.update(b"\0")
    return digest.hexdigest()[:12]


def resolve(force=False):
    release = api("/repos/CyberDrain/CIPP/releases/latest")
    tag = release["tag_name"]
    if release["draft"] or release["prerelease"] or not re.fullmatch(r"v?\d+\.\d+\.\d+", tag):
        raise ValueError("Only an official stable semantic-version release can be built")
    commit = api(f"/repos/CyberDrain/CIPP/commits/{tag}")["sha"]
    if not re.fullmatch(r"[a-f0-9]{40}", commit):
        raise ValueError("Invalid upstream commit")
    base_version = f"{tag.removeprefix('v')}-prometheus.{commit[:8]}.{overlay_hash()}"
    version = base_version
    if force and os.environ.get("GITHUB_RUN_ID"):
        version += f".build.{os.environ['GITHUB_RUN_ID']}"
    state_path = ROOT / "build-state.json"
    state = json.loads(state_path.read_text()) if state_path.exists() else {}
    # A forced rebuild is still the same released source and overlay. Do not
    # republish the old base tag or restart production again on the next check.
    recorded_base = re.sub(r"\.build\.\d+$", "", state.get("version", ""))
    return {"tag": tag, "upstream_sha": commit, "version": version,
            "build": str(force or recorded_base != base_version or
                         state.get("upstream_sha") != commit).lower()}


def prepare(source):
    source = Path(source).resolve()
    catalog_path = source / "frontend/src/data/standards.json"
    catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
    additions = json.loads((ROOT / "standards.json").read_text(encoding="utf-8"))
    if not isinstance(catalog, list) or len(additions) != 1:
        raise ValueError("Unexpected standards catalog format")
    item = additions[0]
    if item["name"] != f"standards.{STANDARD}" or not item["addedComponent"][0]["required"]:
        raise ValueError("Invalid custom standard metadata")
    if [o["value"] for o in item["addedComponent"][0]["options"]] != ["Enabled", "Disabled"]:
        raise ValueError("The standard must require an explicit Enabled/Disabled choice")
    names = [i["name"] for i in catalog]
    if len(names) != len(set(names)) or item["name"] in names:
        raise ValueError("Duplicate standard identifier; stop rather than overwrite")
    destination = source / f"backend/Modules/CIPPStandards/Public/Standards/{SOURCE_FILE}"
    if destination.exists():
        raise ValueError("Upstream already contains the custom function; review before updating")
    helper = (source / "backend/Modules/CIPPCore/Public/GraphHelper/New-TeamsRequestV2.ps1").read_text()
    for parameter in ("TenantFilter", "Type", "Action", "Identity", "Parameters"):
        if f"${parameter}" not in helper:
            raise ValueError(f"Teams request contract changed: missing {parameter}")
    compare = next(source.glob("backend/Modules/**/Set-CIPPStandardsCompareField.ps1"))
    if "$TenantFilter" not in compare.read_text():
        raise ValueError("Standards comparison contract changed")
    if not (source / "build/Dockerfile.release").is_file():
        raise ValueError("Official release Dockerfile is missing")
    # Validate the complete catalog before touching either source file.
    result = catalog + additions
    encoded = json.dumps(result, indent=2, ensure_ascii=False) + "\n"
    if json.loads(encoded)[:-1] != catalog:
        raise ValueError("Existing upstream standards were modified")
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(ROOT / SOURCE_FILE, destination)
    catalog_path.write_text(encoded, encoding="utf-8")
    return len(catalog)


def smoke(app, version):
    app = Path(app)
    module_dir = app / "API/Modules/CIPPStandards"
    manifest = next(module_dir.rglob("CIPPStandards.psd1"))
    module = next(manifest.parent.glob("CIPPStandards.psm1"))
    text = module.read_text(encoding="utf-8-sig")
    if not re.search(rf"function\s+{FUNCTION}\s*\{{", text, re.I):
        raise ValueError("Custom standard was not compiled into the runtime module")
    if "FileSharingInChatsWithExternalUsers" not in text:
        raise ValueError("Compiled policy setting missing")
    manifest_text = manifest.read_text(encoding="utf-8-sig")
    if FUNCTION not in manifest_text and not re.search(r"FunctionsToExport\s*=\s*['\"]\*", manifest_text):
        raise ValueError("Runtime module does not export the custom standard")
    metadata = json.loads((app / "Frontend/version.json").read_text())
    if metadata["version"] != version or metadata["tag"] != "latest":
        raise ValueError("Container version does not match the updater channel")
    javascript = list((app / "Frontend/_next").rglob("*.js"))
    if not any(f"standards.{STANDARD}" in p.read_text(encoding="utf-8") for p in javascript):
        raise ValueError("Custom standard is missing from the built portal catalog")
    for path in ("API/Modules/CIPPCore", "API/Modules/CIPPHTTP", "Frontend/index.html"):
        if not (app / path).exists():
            raise ValueError(f"Required runtime artifact missing: {path}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    commands = parser.add_subparsers(dest="command", required=True)
    plan = commands.add_parser("resolve")
    plan.add_argument("--force", action="store_true")
    commands.add_parser("prepare").add_argument("source")
    check = commands.add_parser("smoke")
    check.add_argument("app")
    check.add_argument("version")
    args = parser.parse_args()
    if args.command == "resolve":
        values = resolve(args.force)
        print(json.dumps(values))
        if os.environ.get("GITHUB_OUTPUT"):
            with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as output:
                for key, value in values.items():
                    output.write(f"{key}={value}\n")
    elif args.command == "prepare":
        print(f"Preserved {prepare(args.source)} upstream standards; added {STANDARD}")
    else:
        smoke(args.app, args.version)
        print("Built backend export, portal catalog, runtime files and updater version verified")
