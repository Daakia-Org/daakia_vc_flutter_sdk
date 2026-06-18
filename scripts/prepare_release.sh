#!/bin/bash
set -e

# Reads the version from pubspec.yaml and syncs it into Constant.sdkVersion,
# then runs flutter pub publish --dry-run to validate the package.

PUBSPEC="pubspec.yaml"
CONSTANTS="lib/utils/constants.dart"

# Extract version from pubspec.yaml
VERSION=$(grep '^version:' "$PUBSPEC" | sed 's/version:[[:space:]]*//')

if [ -z "$VERSION" ]; then
  echo "ERROR: Could not read version from $PUBSPEC"
  exit 1
fi

echo "SDK version: $VERSION"

# Sync into Constant.sdkVersion
sed -i '' "s/static const String sdkVersion = '.*'/static const String sdkVersion = '$VERSION'/" "$CONSTANTS"

echo "Synced Constant.sdkVersion → '$VERSION'"

# Verify the sync worked
if ! grep -q "sdkVersion = '$VERSION'" "$CONSTANTS"; then
  echo "ERROR: Failed to update sdkVersion in $CONSTANTS"
  exit 1
fi

echo "Running dry-run..."
flutter pub publish --dry-run
