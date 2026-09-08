#!/bin/sh
set -e

# Navigate to project root
cd "$CI_PRIMARY_REPOSITORY_PATH"

# Install Flutter
git clone https://github.com/flutter/flutter.git --depth 1 -b stable "$HOME/flutter"
export PATH="$HOME/flutter/bin:$PATH"

# Disable analytics
flutter config --no-analytics

# Pre-cache iOS artifacts (Flutter.xcframework etc.)
# This must run BEFORE pod install, because the Podfile post_install
# hook expects the Flutter engine framework to already exist.
flutter precache --ios

# Get dependencies and generate xcconfig files
flutter pub get

# Install CocoaPods dependencies (now Flutter.xcframework exists)
cd ios
pod install
cd ..

# Build iOS release (generates App.framework, Flutter.framework etc.)
flutter build ios --release --no-codesign
