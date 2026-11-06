#!/bin/bash
# Fails the release if the packageVersion default in any template is not the version
# being released (placeholder left behind, or a stale hand-edited version the stamp skipped).
#
# Usage: verify-template-version.sh <version>
#   <version> is the semantic-release version, e.g. 3.5.0 or 3.5.0-develop.1

set -e

VERSION="$1"

if [ -z "$VERSION" ]; then
  echo "Usage: $0 <version>" >&2
  exit 1
fi

for f in armTemplates/azuredeploy-eventhubforwarder.json armTemplates/azuredeploy-blobforwarder.json; do
  actual=$(node -p "require('./$f').parameters.packageVersion.defaultValue")
  if [ "$actual" != "$VERSION" ]; then
    echo "$f: packageVersion default is '$actual', expected '$VERSION'" >&2
    exit 1
  fi
done

for f in bicep/azuredeploy-eventhubforwarder.bicep bicep/azuredeploy-blobforwarder.bicep; do
  if ! grep -qF "param packageVersion string = '$VERSION'" "$f"; then
    echo "$f: packageVersion default is not '$VERSION'" >&2
    exit 1
  fi
done
