#!/usr/bin/env bash
# Creates a stable self-signed code-signing identity ("Tab Dev") in your login
# keychain. Once it exists, build-app.sh signs every build with the SAME identity,
# so macOS keeps your Accessibility / Screen Recording grants across rebuilds
# (ad-hoc signing changes the binary hash each time and resets them).
#
# Run it once:   bash scripts/setup-signing.sh
# No password needed — the key is imported with -A (accessible to all apps), so
# codesign can use it without a keychain partition-list prompt.
set -uo pipefail

NAME="Tab Dev"
KC="$HOME/Library/Keychains/login.keychain-db"
# macOS's own OpenSSL (LibreSSL). Homebrew's OpenSSL 3.x exports a .p12 that
# `security import` can't read without -legacy, which silently breaks setup.
OPENSSL="/usr/bin/openssl"

if security find-identity -p codesigning 2>/dev/null | grep -q "$NAME"; then
    echo "✓ Signing identity '$NAME' already exists. Nothing to do."
    exit 0
fi

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

cat > "$T/cfg" <<'EOF'
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = Tab Dev
[v3]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

echo "▸ Generating a self-signed code-signing certificate (LibreSSL)…"
"$OPENSSL" req -x509 -newkey rsa:2048 -keyout "$T/key.pem" -out "$T/cert.pem" \
    -days 3650 -nodes -config "$T/cfg" >/dev/null 2>&1
"$OPENSSL" pkcs12 -export -inkey "$T/key.pem" -in "$T/cert.pem" \
    -out "$T/tab.p12" -name "$NAME" -passout pass:tab >/dev/null 2>&1

echo "▸ Importing it into your login keychain…"
security import "$T/tab.p12" -k "$KC" -P tab -A -T /usr/bin/codesign

if security find-identity -p codesigning | grep -q "$NAME"; then
    echo "✓ '$NAME' is ready. Now run:  ./scripts/build-app.sh release"
    echo "  You'll grant Accessibility (and Screen Recording for previews) one last time."
else
    echo "✗ Import didn't register the identity. Tell Claude — something's off."
    exit 1
fi
