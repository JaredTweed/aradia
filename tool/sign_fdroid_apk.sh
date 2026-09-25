#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 UNSIGNED_APK SIGNED_APK" >&2
  exit 2
fi

: "${ARADIA_FDROID_KEYSTORE:?Set ARADIA_FDROID_KEYSTORE to the private PKCS#12 keystore path}"
: "${ARADIA_FDROID_KEYSTORE_PASS:?Set ARADIA_FDROID_KEYSTORE_PASS to the keystore password}"

apksigner_bin="${ARADIA_APKSIGNER:-apksigner}"
apksigcopier_bin="${ARADIA_APKSIGCOPIER:-apksigcopier}"
apksigner_path="$(command -v "$apksigner_bin")"
export PATH="$(dirname "$apksigner_path"):$PATH"

# Re-aligning ZIP entries changes the APK bytes and breaks F-Droid's signature
# copy verification, even if all uncompressed files are identical.
"$apksigner_bin" sign \
  --alignment-preserved true \
  --v1-signing-enabled false \
  --ks "$ARADIA_FDROID_KEYSTORE" \
  --ks-type PKCS12 \
  --ks-key-alias aradia-fdroid \
  --ks-pass env:ARADIA_FDROID_KEYSTORE_PASS \
  --key-pass env:ARADIA_FDROID_KEYSTORE_PASS \
  --out "$2" "$1"

"$apksigner_bin" verify "$2"
"$apksigcopier_bin" compare "$2" --unsigned "$1"
