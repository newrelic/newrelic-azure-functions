#!/bin/bash
# Publishes the release ZIP + checksum to Azure Blob Storage. For develop
# prereleases (version contains a '-'), also self-cleans stale test builds
# older than 30 days.
#
# Usage: publish-release.sh <version>
#   <version> is the semantic-release version, e.g. 3.4.0 or 3.4.0-develop.1

set -e

VERSION="$1"
ACCOUNT="nrloggingprodreleases"
CONTAINER="releases"

if [ -z "$VERSION" ]; then
  echo "Usage: $0 <version>" >&2
  exit 1
fi

sha256sum LogForwarder.zip > LogForwarder.zip.sha256

# --overwrite false: fail loudly an already-published version.
az storage blob upload \
  --account-name "$ACCOUNT" --container-name "$CONTAINER" \
  --name "log-forwarder-$VERSION.zip" --file LogForwarder.zip \
  --auth-mode login --overwrite false

az storage blob upload \
  --account-name "$ACCOUNT" --container-name "$CONTAINER" \
  --name "log-forwarder-$VERSION.zip.sha256" --file LogForwarder.zip.sha256 \
  --auth-mode login --overwrite false

case "$VERSION" in
  *-*)
    CUTOFF=$(date -u -d '30 days ago' +%Y-%m-%dT%H:%M:%SZ)
    az storage blob list \
      --account-name "$ACCOUNT" --container-name "$CONTAINER" --auth-mode login \
      --query "[?contains(name, '-develop.') && properties.lastModified < '$CUTOFF'].name" \
      -o tsv \
      | xargs -r -I{} az storage blob delete \
          --account-name "$ACCOUNT" --container-name "$CONTAINER" \
          --name {} --auth-mode login \
      || echo "::warning::cleanup of stale develop prerelease blobs failed"
    ;;
esac
