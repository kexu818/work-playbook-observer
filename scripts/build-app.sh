#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# SwiftPM's Xcode build backend otherwise stamps the deployment target as the
# linked SDK (14.0), keeping AppKit/SwiftUI in the legacy design on new macOS.
task_sdk_version="$(xcrun --sdk macosx --show-sdk-version)"
task_bundle_id="${PLAYBOOK_BUNDLE_ID:-io.github.kexu818.work-playbook-observer}"
swift build -c release -Xlinker -platform_version -Xlinker macos -Xlinker 14.0 -Xlinker "$task_sdk_version"
app="dist/Playbook 工作台.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/release/PlaybookWorkbench "$app/Contents/MacOS/PlaybookWorkbench"
cp backend/history.py "$app/Contents/Resources/history.py"
cp backend/codex_runner.py "$app/Contents/Resources/codex_runner.py"
# Compile the approved master through Apple's app-icon asset pipeline.
task_icon_assets="$PWD/.build/Branding.xcassets"
task_icon_set="$task_icon_assets/AppIcon.appiconset"
mkdir -p "$task_icon_set"
swift scripts/render-app-icon.swift assets/branding/playbook-icon-v1.png .build/AppIcon-normalized.png
python3 - "$task_icon_assets" <<'PY'
import json, pathlib, subprocess, sys
catalog = pathlib.Path(sys.argv[1])
images = []
for size in (16, 32, 128, 256, 512):
    for scale in (1, 2):
        name = f'icon-{size}@{scale}x.png'
        subprocess.run(['sips', '-z', str(size * scale), str(size * scale),
                        '.build/AppIcon-normalized.png', '--out', str(catalog / 'AppIcon.appiconset' / name)],
                       check=True, stdout=subprocess.DEVNULL)
        images.append({'idiom': 'mac', 'size': f'{size}x{size}', 'scale': f'{scale}x', 'filename': name})
(catalog / 'Contents.json').write_text(json.dumps({'info': {'author': 'xcode', 'version': 1}}))
(catalog / 'AppIcon.appiconset/Contents.json').write_text(json.dumps({'images': images, 'info': {'author': 'xcode', 'version': 1}}))
PY
xcrun actool "$task_icon_assets" --compile "$PWD/$app/Contents/Resources" \
  --platform macosx --minimum-deployment-target 14.0 --app-icon AppIcon \
  --output-partial-info-plist "$PWD/.build/icon-info.plist" --output-format human-readable-text
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>PlaybookWorkbench</string>
<key>CFBundleIdentifier</key><string>io.github.kexu818.work-playbook-observer</string>
<key>CFBundleName</key><string>Playbook 工作台</string>
<key>CFBundleVersion</key><string>7</string>
<key>CFBundleShortVersionString</key><string>0.2.6</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
/usr/libexec/PlistBuddy -c "Add :DTSDKName string macosx$task_sdk_version" "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $task_bundle_id" "$app/Contents/Info.plist"
python3 - "$app/Contents/Info.plist" .build/icon-info.plist <<'PY'
import pathlib, plistlib, sys
target = pathlib.Path(sys.argv[1])
info = plistlib.loads(target.read_bytes())
info.update(plistlib.loads(pathlib.Path(sys.argv[2]).read_bytes()))
target.write_bytes(plistlib.dumps(info))
PY
codesign --force --sign - "$app"
printf '%s\n' "$PWD/$app"
