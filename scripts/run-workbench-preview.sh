#!/bin/zsh
set -euo pipefail

# Run a separate app identity and data store so UI validation cannot overwrite
# the installed app's conversations, API key, preferences, or MCP configuration.
validation_root="${BEDROCK_PREVIEW_ROOT:-/tmp/bedrock-pilot-validation}"
if [[ $# -ne 1 || ! -f "$1/Contents/Info.plist" ]]; then
    print -u2 'Pass the app you just built, for example:'
    print -u2 '  scripts/run-workbench-preview.sh ".build/xcode/Build/Products/Release/Amazon Bedrock.app"'
    exit 2
fi
source_app="${1:A}"
validation_root="${validation_root:A}"
preview_app="$validation_root/Bedrock Validation.app"
preview_bundle="${BEDROCK_PREVIEW_BUNDLE_IDENTIFIER:-AWS.Amazon-Bedrock-Client-for-Mac.PilotValidation}"
if [[ "$source_app" == "${preview_app:A}" ]]; then
    print -u2 'The built app and preview destination must be different.'
    exit 2
fi
ensure_preview_stopped() {
    python3 - "$preview_app" <<'PY'
from pathlib import Path
import plistlib
import subprocess
import sys

app = Path(sys.argv[1])
info = app / "Contents/Info.plist"
if not info.exists():
    sys.exit(0)
executable = (app / "Contents/MacOS" / plistlib.loads(info.read_bytes())["CFBundleExecutable"]).resolve()
processes = subprocess.run(["ps", "-axo", "pid=,comm="], check=True, capture_output=True, text=True)
for line in processes.stdout.splitlines():
    fields = line.strip().split(None, 1)
    if len(fields) == 2 and Path(fields[1]).is_absolute() and Path(fields[1]).resolve() == executable:
        print("Quit the running preview before replacing its executable. Its data will be retained.", file=sys.stderr)
        sys.exit(2)
PY
}
ensure_preview_stopped
mkdir -p "$validation_root/app-data"
staging_root=$(mktemp -d "$validation_root/.preview-build.XXXXXX")
trap 'rm -rf "$staging_root"' EXIT
staged_app="$staging_root/Bedrock Validation.app"
# Copy into a fresh bundle so removed sources/resources cannot survive an update.
ditto "$source_app" "$staged_app"
python3 - "$source_app" "$staged_app" <<'PY'
from pathlib import Path
import hashlib
import plistlib
import sys

def digest(app):
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    return hashlib.sha256((app / "Contents/MacOS" / info["CFBundleExecutable"]).read_bytes()).digest()

if digest(Path(sys.argv[1])) != digest(Path(sys.argv[2])):
    sys.exit("The staged executable differs from the selected build; the preview was not replaced.")
PY
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $preview_bundle" "$staged_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName Bedrock Validation" "$staged_app/Contents/Info.plist"
# Keep isolation when Launch Services reopens the preview after Quit.
/usr/libexec/PlistBuddy -c "Add :LSEnvironment dict" "$staged_app/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Delete :LSEnvironment:BEDROCK_WORKBENCH_DATA_DIR" "$staged_app/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :LSEnvironment:BEDROCK_WORKBENCH_DATA_DIR string $validation_root/app-data" "$staged_app/Contents/Info.plist"
codesign --force --deep --sign - "$staged_app" > "$validation_root/preview-sign.log" 2>&1
codesign --verify --deep --strict "$staged_app"
ensure_preview_stopped
previous_app=""
if [[ -d "$preview_app" ]]; then
    mkdir -p "$validation_root/previous-builds"
    previous_root=$(mktemp -d "$validation_root/previous-builds/build.XXXXXX")
    previous_app="$previous_root/Bedrock Validation.app"
    mv "$preview_app" "$previous_app"
fi
if ! mv "$staged_app" "$preview_app"; then
    [[ -z "$previous_app" ]] || mv "$previous_app" "$preview_app"
    print -u2 'Could not install the staged build; the previous preview was restored.'
    exit 1
fi
if ! defaults read "$preview_bundle" previewInitialized >/dev/null 2>&1; then
    defaults write "$preview_bundle" previewInitialized -bool YES
    defaults write "$preview_bundle" checkForUpdates -bool NO
    defaults write "$preview_bundle" enableQuickAccess -bool NO
    defaults write "$preview_bundle" enableDebugLog -bool NO
    defaults write "$preview_bundle" mcpEnabled -bool NO
    defaults write "$preview_bundle" selectedRegion -string us-east-1
    defaults write "$preview_bundle" selectedProfile -string default
    defaults write "$preview_bundle" defaultModelId -string us.amazon.nova-micro-v1:0
fi
preview_executable=$(/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable" "$preview_app/Contents/Info.plist")
python3 - "$source_app" "$preview_app" "$validation_root/preview-build.json" <<'PY'
from pathlib import Path
import hashlib
import json
import plistlib
import sys

source, preview, receipt = map(Path, sys.argv[1:])
def identity(app):
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    executable = app / "Contents/MacOS" / info["CFBundleExecutable"]
    return {
        "app": str(app),
        "bundle": info["CFBundleIdentifier"],
        "version": info.get("CFBundleShortVersionString"),
        "build": info.get("CFBundleVersion"),
        "executable_sha256": hashlib.sha256(executable.read_bytes()).hexdigest(),
    }
record = {"source": identity(source), "preview": identity(preview)}
receipt.write_text(json.dumps(record, indent=2) + "\n")
print(f"Launching {record['preview']['app']} (build {record['preview']['build']})")
print(f"Build receipt: {receipt}")
PY
[[ -z "$previous_app" ]] || print "Previous app: $previous_app"
rm -rf "$staging_root"
trap - EXIT
exec env BEDROCK_WORKBENCH_DATA_DIR="$validation_root/app-data" "$preview_app/Contents/MacOS/$preview_executable"
