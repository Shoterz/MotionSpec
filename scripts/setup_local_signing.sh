#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG_FILE="${MOTIONSPEC_PACKAGE_CONFIG:-$ROOT_DIR/.motionspec-package.env}"
IDENTITY="${MOTIONSPEC_LOCAL_IDENTITY:-MotionSpec Local Development}"
KEYCHAIN="${MOTIONSPEC_KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"
CERT_DAYS="${MOTIONSPEC_LOCAL_CERT_DAYS:-3650}"

find_preferred_identity() {
  security find-identity -v -p codesigning \
    | sed -nE 's/^[[:space:]]*[0-9]+\) [A-Fa-f0-9]+ "(Apple Development:[^"]+)".*/\1/p; s/^[[:space:]]*[0-9]+\) [A-Fa-f0-9]+ "(Developer ID Application:[^"]+)".*/\1/p' \
    | head -n 1
}

identity_exists() {
  security find-identity -v -p codesigning | grep -Fq "\"$IDENTITY\""
}

write_package_config() {
  cat > "$CONFIG_FILE" <<EOF
CODESIGN_IDENTITY="$IDENTITY"
EOF
  chmod 600 "$CONFIG_FILE"
}

if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
  IDENTITY="$CODESIGN_IDENTITY"
  write_package_config
  echo "Using exported code-signing identity: $IDENTITY"
  echo "Wrote $CONFIG_FILE"
  exit 0
fi

PREFERRED_IDENTITY="$(find_preferred_identity)"
if [[ -n "$PREFERRED_IDENTITY" ]]; then
  IDENTITY="$PREFERRED_IDENTITY"
  write_package_config
  echo "Using existing Apple code-signing identity: $IDENTITY"
  echo "Wrote $CONFIG_FILE"
  exit 0
fi

if identity_exists; then
  write_package_config
  echo "Using existing code-signing identity: $IDENTITY"
  echo "Wrote $CONFIG_FILE"
  exit 0
fi

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/motionspec-signing.XXXXXX")"
cleanup() {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

OPENSSL_CONFIG="$WORK_DIR/codesign.cnf"
PRIVATE_KEY="$WORK_DIR/identity.key"
CERTIFICATE="$WORK_DIR/identity.crt"
PKCS12="$WORK_DIR/identity.p12"
PKCS12_PASSWORD="$(uuidgen)"

cat > "$OPENSSL_CONFIG" <<EOF
[req]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
x509_extensions = codesign_ext

[dn]
CN = $IDENTITY

[codesign_ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = codeSigning
subjectKeyIdentifier = hash
EOF

openssl req \
  -newkey rsa:2048 \
  -nodes \
  -keyout "$PRIVATE_KEY" \
  -x509 \
  -days "$CERT_DAYS" \
  -out "$CERTIFICATE" \
  -config "$OPENSSL_CONFIG"

openssl pkcs12 \
  -export \
  -inkey "$PRIVATE_KEY" \
  -in "$CERTIFICATE" \
  -out "$PKCS12" \
  -passout "pass:$PKCS12_PASSWORD"

security import "$PKCS12" \
  -k "$KEYCHAIN" \
  -P "$PKCS12_PASSWORD" \
  -T /usr/bin/codesign \
  -T /usr/bin/security

security add-trusted-cert \
  -r trustRoot \
  -p codeSign \
  -k "$KEYCHAIN" \
  "$CERTIFICATE"

write_package_config

if ! identity_exists; then
  echo "Created $IDENTITY, but macOS did not list it as a valid code-signing identity." >&2
  echo "Open Keychain Access and set the certificate to Always Trust for Code Signing, then rerun this script." >&2
  exit 1
fi

echo "Created code-signing identity: $IDENTITY"
echo "Wrote $CONFIG_FILE"
echo "Future rebuilds will use this identity through scripts/package_app.sh"
