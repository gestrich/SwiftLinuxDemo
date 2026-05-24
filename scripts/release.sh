#!/bin/bash
set -euo pipefail

VERSION="${1:-}"

if [[ -z "$VERSION" ]]; then
    echo "error: version argument required" >&2
    echo "usage: $0 v0.1.0" >&2
    exit 1
fi

if [[ "$VERSION" != v* ]]; then
    echo "error: version must start with 'v' (got: $VERSION)" >&2
    echo "       (the workflow trigger glob is 'v*' — non-v tags fire nothing)" >&2
    exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
    echo "error: working tree is not clean — commit or stash changes first" >&2
    exit 1
fi

if git tag --list | grep -qx "$VERSION"; then
    echo "error: tag $VERSION already exists locally" >&2
    exit 1
fi

if git ls-remote --tags origin | grep -q "refs/tags/$VERSION$"; then
    echo "error: tag $VERSION already exists on remote" >&2
    exit 1
fi

git tag "$VERSION"
git push origin "$VERSION"

REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')
echo "Tag $VERSION pushed. Watch the release workflow at:"
echo "  https://github.com/$REPO/actions/workflows/release.yml"
