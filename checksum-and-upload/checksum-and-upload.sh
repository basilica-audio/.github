#!/usr/bin/env bash
#
# Computes a sha256 checksum for each given release archive and uploads the
# archive together with its `<name>.sha256` file to the GitHub release for
# the tag - so a downloader can always verify a download byte for byte, and
# the shape of that pairing lives in exactly one place across the suite
# (basilica-audio/.github#5) rather than being re-typed into every repo's
# release.yml, where it can be - and was - forgotten.
#
# `<name>.sha256` is written in the `sha256sum -c` / `shasum -a 256 -c`
# format (`<hex>  <name>`, two spaces, relative filename) on every platform:
# Linux's and Windows Git-Bash's `sha256sum` and macOS's `shasum -a 256`
# already emit exactly that format on their own, so no reformatting step is
# needed here - the file only has to come from the right tool for the
# runner it is built on. `sha256sum` is preferred when present (Linux and
# Windows/Git-Bash); `shasum -a 256` is the fallback (macOS, which ships no
# `sha256sum`).
#
# Called only through ./action.yml, which supplies every INPUT_*.

set -euo pipefail

TAG="${INPUT_TAG:?tag input is required}"
REPO="${INPUT_REPOSITORY:?repository input is required}"
ASSETS="${INPUT_ASSETS:?assets input is required}"

sha256_file() {
    local file="$1"
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$file"
    else
        shasum -a 256 "$file"
    fi
}

# Word-splits INPUT_ASSETS on IFS (spaces and newlines) - deliberate rather
# than an array-preserving read, since every caller passes filenames its own
# build step just produced, never anything with embedded whitespace.
# shellcheck disable=SC2206
ASSET_LIST=($ASSETS)

if [ "${#ASSET_LIST[@]}" -eq 0 ]; then
    echo "::error::checksum-and-upload: no assets given"
    exit 1
fi

for ASSET in "${ASSET_LIST[@]}"; do
    if [ ! -f "$ASSET" ]; then
        echo "::error::checksum-and-upload: $ASSET not found"
        exit 1
    fi

    CHECKSUM_FILE="$ASSET.sha256"
    sha256_file "$ASSET" > "$CHECKSUM_FILE"
    echo "Uploading $ASSET and $CHECKSUM_FILE to $TAG ($REPO)"
    gh release upload "$TAG" "$ASSET" "$CHECKSUM_FILE" --clobber -R "$REPO"
done
