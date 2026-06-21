#!/usr/bin/env bash
# Creates a stable self-signed code-signing identity ("Tab Dev") in your login
# keychain. Once it exists, build-app.sh signs every build with the SAME identity,
# so macOS keeps your Accessibility / Screen Recording grants across rebuilds
# (ad-hoc signing changes the binary hash each time and resets them).
#
# Run it once:   bash scripts/setup-signing.sh
# You'll be asked for your macOS login password (needed to authorize codesign to
# use the new key — it is only passed to the local `security` tool, nothing else).
set -euo pipefail

IDENTITY_NAME="Tab Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning 2>/dev/null | grep -q "$IDENTITY_NAME"; then
    echo "✓ Signing identity '$IDENTITY_NAME' already exists. Nothing to do."
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cfg" <<'EOF'
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

echo "▸ Generating a self-signed code-signing certificate…"
openssl req -x509 -newkey rsa:2048 -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
    -days 3650 -nodes -config "$TMP/cfg" >/dev/null 2>&1
openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -out "$TMP/tab.p12" -name "$IDENTITY_NAME" -passout pass:tab >/dev/null 2>&1

echo "▸ Importing it into your login keychain…"
security import "$TMP/tab.p12" -k "$KEYCHAIN" -P tab -T /usr/bin/codesign >/dev/null

echo "▸ Authorizing codesign to use the key."
read -r -s -p "  Enter your macOS login password: " PW; echo
security set-key-partition-list -S apple-tool:,apple: -s -k "$PW" "$KEYCHAIN" >/dev/null 2>&1 || {
    echo "⚠ Could not set the key partition list (wrong password?). codesign may prompt you on first use."
}

if security find-identity -v -p codesigning | grep -q "$IDENTITY_NAME"; then
    echo "✓ '$IDENTITY_NAME' is ready. Now run:  ./scripts/build-app.sh release"
    echo "  You'll grant Accessibility (and Screen Recording for previews) one last time."
else
    echo "⚠ Created the identity but find-identity didn't list it. Signing may still work; if not, tell Claude."
fi
