#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if ! command -v xcodebuild >/dev/null 2>&1; then
    echo "Poochi Analytics needs Xcode on a Mac to build."
    exit 1
fi
swift test
xcodebuild -project PoochiAnalytics.xcodeproj -scheme PoochiAnalytics \
    -configuration Release -destination 'generic/platform=macOS' \
    -derivedDataPath build ONLY_ACTIVE_ARCH=NO ARCHS='arm64 x86_64' \
    CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual build
mkdir -p build/deliverables
ditto -c -k --sequesterRsrc --keepParent \
    'build/Build/Products/Release/Poochi Analytics.app' 'build/deliverables/Poochi-Analytics-macOS.zip'
echo "Built build/Build/Products/Release/Poochi Analytics.app"
