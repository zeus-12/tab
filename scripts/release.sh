#!/usr/bin/env bash
# One-command release: bump version, commit, tag, push. CI (.github/workflows/
# release.yml) reacts to the pushed tag and publishes the GitHub Release with the
# built app attached. The git tag is the source of truth; the Info.plist bump just
# keeps local builds honest (CI re-derives the version from the tag).
#
# Usage:  bash scripts/release.sh 0.2.0
set -euo pipefail

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
    echo "usage: bash scripts/release.sh <version>   e.g. 0.2.0" >&2
    exit 1
fi
VERSION="${VERSION#v}"   # tolerate a leading v
TAG="v$VERSION"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [[ "$BRANCH" != "main" ]]; then
    echo "✗ Releases must be cut from 'main' (you're on '$BRANCH')." >&2
    exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
    echo "✗ Working tree is dirty — commit or stash first." >&2
    exit 1
fi

if git rev-parse "$TAG" >/dev/null 2>&1; then
    echo "✗ Tag $TAG already exists." >&2
    exit 1
fi

echo "▸ Stamping $VERSION into Resources/Info.plist…"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" Resources/Info.plist

git add Resources/Info.plist
git commit -m "Release $TAG"
git tag "$TAG"

echo "▸ Pushing main and $TAG…"
git push origin main
git push origin "$TAG"

echo "✓ Pushed $TAG — CI is building and will publish the release."
echo "  Watch: https://github.com/zeus-12/tab/actions"
