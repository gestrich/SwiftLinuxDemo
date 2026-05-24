#!/bin/sh
set -eu

REPO="gestrich/SwiftLinuxDemo"
BINARY="swift-linux-demo"
INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"

OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)

case "${OS}-${ARCH}" in
    linux-x86_64)
        PLATFORM="linux-x86_64"
        ;;
    darwin-*)
        echo "error: ${REPO} ships only Linux binaries by design." >&2
        echo "       On macOS, clone the repo and run 'swift build -c release'." >&2
        exit 1
        ;;
    *)
        echo "error: unsupported platform ${OS}-${ARCH}" >&2
        echo "       supported: linux-x86_64" >&2
        exit 1
        ;;
esac

if [ -z "${VERSION:-}" ]; then
    VERSION=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" | \
        grep '"tag_name"' | sed 's/.*"tag_name": *"\([^"]*\)".*/\1/')
    if [ -z "$VERSION" ]; then
        echo "error: could not determine latest release version" >&2
        exit 1
    fi
fi

echo "Installing ${BINARY} ${VERSION} for ${PLATFORM}..."

TARBALL="${BINARY}-${PLATFORM}.tar.gz"
BASE_URL="https://github.com/${REPO}/releases/download/${VERSION}"

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

curl -fsSL "${BASE_URL}/${TARBALL}" -o "${TMP_DIR}/${TARBALL}"
curl -fsSL "${BASE_URL}/checksums.txt" -o "${TMP_DIR}/checksums.txt"

EXPECTED=$(grep " ${TARBALL}" "${TMP_DIR}/checksums.txt" | awk '{print $1}')
if [ -z "$EXPECTED" ]; then
    echo "error: checksum not found for ${TARBALL}" >&2
    exit 1
fi

if command -v sha256sum >/dev/null 2>&1; then
    ACTUAL=$(sha256sum "${TMP_DIR}/${TARBALL}" | awk '{print $1}')
elif command -v shasum >/dev/null 2>&1; then
    ACTUAL=$(shasum -a 256 "${TMP_DIR}/${TARBALL}" | awk '{print $1}')
else
    echo "error: no SHA256 tool found (sha256sum or shasum)" >&2
    exit 1
fi

if [ "$ACTUAL" != "$EXPECTED" ]; then
    echo "error: checksum mismatch for ${TARBALL}" >&2
    echo "  expected: ${EXPECTED}" >&2
    echo "  actual:   ${ACTUAL}" >&2
    exit 1
fi
echo "Checksum verified."

tar -xzf "${TMP_DIR}/${TARBALL}" -C "${TMP_DIR}"

EXTRACTED_BINARY="${TMP_DIR}/${BINARY}"
DEST="${INSTALL_DIR}/${BINARY}"

do_install() {
    mkdir -p "${INSTALL_DIR}"
    cp "${EXTRACTED_BINARY}" "${DEST}"
    chmod +x "${DEST}"
}

if do_install 2>/dev/null; then
    :
elif command -v sudo >/dev/null 2>&1; then
    echo "Permission denied — retrying with sudo..."
    sudo sh -c "mkdir -p '${INSTALL_DIR}' && cp '${EXTRACTED_BINARY}' '${DEST}' && chmod +x '${DEST}'"
else
    echo "error: cannot write to ${INSTALL_DIR} — try setting INSTALL_DIR to a directory you own (e.g., INSTALL_DIR=~/.local/bin)" >&2
    exit 1
fi

echo "Installed ${BINARY} to ${DEST}"

if "${DEST}" --version >/dev/null 2>&1; then
    echo "${BINARY} is working. Try: ${BINARY} info"
else
    echo "warning: ${DEST} did not respond to --version" >&2
fi

echo
echo "To cryptographically verify the binary came from this exact workflow run:"
echo "  gh attestation verify ${TARBALL} --repo ${REPO}"
