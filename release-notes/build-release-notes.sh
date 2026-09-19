#!/usr/bin/env bash
#
# Builds a Basilica Audio release body and publishes it onto the release for the
# tag, creating that release if it does not exist yet.
#
# The body is the repository's own CHANGELOG.md section for the tag, followed by
# a footer that is identical across all thirteen plugins: what each attached
# archive contains, what is signed and what is not, and where the files go.
#
# Called only through ./action.yml, which supplies every INPUT_*.

set -euo pipefail

TAG="${INPUT_TAG:?tag input is required}"
REPO="${INPUT_REPOSITORY:?repository input is required}"
CHANGELOG="${INPUT_CHANGELOG:-CHANGELOG.md}"
MANUAL_PATH="${INPUT_MANUAL_PATH:-docs/manual.md}"
INCLUDE_ASSETS="${INPUT_INCLUDE_ASSETS:-false}"
ALLOW_MISSING="${INPUT_ALLOW_MISSING_CHANGELOG_SECTION:-false}"
DRY_RUN="${INPUT_DRY_RUN:-false}"

VERSION="${TAG#v}"
PLUGIN="${REPO##*/}"
SLUG="$(printf '%s' "$PLUGIN" | tr '[:upper:]' '[:lower:]')"
PRODUCT_PAGE="${INPUT_PRODUCT_PAGE:-}"
[ -n "$PRODUCT_PAGE" ] || PRODUCT_PAGE="https://basilica-audio.github.io/website/${SLUG}/"

WORK="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
BODY="$WORK/release-body.md"
SECTION="$WORK/release-section.md"

# ==============================================================================
# 1. The CHANGELOG section for this tag.
# ==============================================================================
# Prints everything between `## [<version>]` and the next `## [` heading, so the
# heading itself and the link-reference block at the bottom of a Keep a Changelog
# file are both left out. The version is regex-escaped before it is used as a
# pattern: unescaped, the dots in `0.7.0` would also match `0x7y0`.
if [ ! -f "$CHANGELOG" ]; then
    echo "::error::$CHANGELOG not found. The release body is built from it - is the repository checked out?"
    exit 1
fi

awk -v ver="$VERSION" '
    BEGIN {
        gsub(/[.\\^$(){}\[\]*+?|]/, "\\\\&", ver)
        pattern = "^## \\[" ver "\\]"
        found = 0
    }
    /^## \[/ {
        if (found) exit
        if ($0 ~ pattern) { found = 1; next }
    }
    found
' "$CHANGELOG" > "$SECTION"

# Trim leading and trailing blank lines so the body never opens or closes with
# whitespace, whatever the changelog's own spacing happens to be. Command
# substitution strips the trailing newlines; the sed strips the leading ones.
SECTION_TEXT="$(sed -e '/./,$!d' "$SECTION")"

if [ -z "$SECTION_TEXT" ]; then
    if [ "$ALLOW_MISSING" = "true" ]; then
        echo "::warning::No '## [$VERSION]' section in $CHANGELOG - publishing the footer alone."
        SECTION_TEXT="_This release has no changelog entry._"
    else
        echo "::error::No '## [$VERSION]' section in $CHANGELOG. Add one and re-tag rather than shipping a release page that says nothing; set allow-missing-changelog-section to bypass."
        exit 1
    fi
fi

# ==============================================================================
# 2. The Downloads table, from the assets actually attached.
# ==============================================================================
# Only meaningful once the platform jobs have uploaded, so the release-creating
# job passes include-assets=false and gets this section omitted. Descriptions are
# matched by suffix, and an asset this mapping has never seen still gets a row
# rather than being dropped.
#
# basilica-audio/.github#5: an archive uploaded without a matching `.sha256`
# fails this step - and so the workflow run - rather than shipping quietly.
# assert_checksum_pairing runs against the same $names listing before any row
# is rendered, so a missing pairing is caught even on a release with no other
# problem worth a Downloads-table row.
assert_checksum_pairing() {
    local names="$1"
    local archive_names="" checksum_stems="" name

    while IFS= read -r name; do
        [ -n "$name" ] || continue
        case "$name" in
            *.sha256) checksum_stems="${checksum_stems}${name%.sha256}"$'\n' ;;
            *) archive_names="${archive_names}${name}"$'\n' ;;
        esac
    done <<< "$names"

    local missing="" archive
    while IFS= read -r archive; do
        [ -n "$archive" ] || continue
        if ! grep -qxF "$archive" <<< "$checksum_stems"; then
            missing="${missing}${archive}"$'\n'
        fi
    done <<< "$archive_names"

    if [ -n "$missing" ]; then
        echo "::error::Release $TAG has archive(s) uploaded with no matching .sha256 (basilica-audio/.github#5): $(tr '\n' ' ' <<< "$missing")"
        return 1
    fi
}

render_downloads() {
    local names="$1"
    local rows="" checksums=0 name description
    while IFS= read -r name; do
        [ -n "$name" ] || continue
        case "$name" in
            *.sha256)
                checksums=1
                continue
                ;;
            *-macos.zip)
                description='AU (`.component`), VST3 (`.vst3`) and Standalone (`.app`) - Universal Binary, arm64 + x86_64, macOS 11.0 or later' ;;
            *-macos.pkg)
                description='Installer placing the AU, VST3 and Standalone in the standard locations - Universal Binary, arm64 + x86_64, macOS 11.0 or later' ;;
            *-windows.zip)
                description='VST3 (`.vst3`) and Standalone (`.exe`) - 64-bit, Windows 10 or later' ;;
            *)
                description='' ;;
        esac
        rows="${rows}| \`${name}\` | ${description} |"$'\n'
    done <<< "$names"

    [ -n "$rows" ] || return 0

    printf '## Downloads\n\n| Asset | Contains |\n| --- | --- |\n%s' "$rows"

    if [ "$checksums" -eq 1 ]; then
        printf '\nEvery archive is published alongside a `.sha256` file holding the checksum the build produced. Verify a download with `shasum -a 256 -c <file>.sha256` on macOS/Linux, or on Windows `certutil -hashfile <file> SHA256` and compare the printed hash against the `.sha256` file.\n'
    fi

    printf '\n'
}

DOWNLOADS=""
if [ "$INCLUDE_ASSETS" = "true" ]; then
    ASSET_NAMES="$(gh release view "$TAG" -R "$REPO" --json assets --jq '.assets[].name' 2>/dev/null || true)"

    # Run as a plain top-level statement, not inside the $(...) below: a
    # command substitution runs in a subshell where `set -e` is NOT inherited
    # by default (bash's `inherit_errexit` is off unless a caller opted in),
    # so a `return 1` from inside `render_downloads() { ...; assert_...; }`
    # would otherwise be swallowed and the release would still publish. The
    # explicit `|| exit 1` is defense in depth on top of that, not a
    # substitute for keeping the call itself at top level.
    assert_checksum_pairing "$ASSET_NAMES" || exit 1

    DOWNLOADS="$(render_downloads "$ASSET_NAMES")"
fi

# ==============================================================================
# 3. Assemble.
# ==============================================================================
{
    printf '## What changed in %s\n\n' "$TAG"
    printf '%s\n\n' "$SECTION_TEXT"
    printf -- '---\n\n'

    # Trailing newlines are stripped by the command substitution that produced
    # $DOWNLOADS, so the blank line before the next heading is re-added here.
    [ -z "$DOWNLOADS" ] || printf '%s\n\n' "$DOWNLOADS"

    cat <<FOOTER
## Signing

- **macOS - signed, notarised and stapled.** Every bundle carries a Developer ID
  Application signature, has been through Apple's notary service, and has the
  notarisation ticket stapled to it, so it opens on a clean machine without a
  Gatekeeper warning and without the right-click detour. Check it yourself with
  \`codesign --verify --strict --verbose=2 <bundle>\` and
  \`spctl -a -t open --context context:primary-signature <bundle>\`.
- **Windows - not code-signed.** There is no Authenticode certificate behind
  these builds. SmartScreen will show "Windows protected your PC" the first time
  you run the Standalone; if you trust the download, choose **More info** and
  then **Run anyway**. Stated here rather than left for you to discover.

## Install

**macOS** - copy each bundle out of the archive to:

| Format | Destination |
| --- | --- |
| AU (\`${PLUGIN}.component\`) | \`~/Library/Audio/Plug-Ins/Components/\` |
| VST3 (\`${PLUGIN}.vst3\`) | \`~/Library/Audio/Plug-Ins/VST3/\` |
| Standalone (\`${PLUGIN}.app\`) | \`/Applications/\` |

Replace any earlier copy rather than keeping both. If your host still lists the
previous build, or the AU does not show up at all, the Audio Unit cache needs a
nudge:

\`\`\`sh
killall -9 AudioComponentRegistrar
auval -a | grep -i ${PLUGIN}
\`\`\`

**Windows** - copy \`${PLUGIN}.vst3\` to \`%CommonProgramFiles%\\VST3\\\`, and put
\`${PLUGIN}.exe\` wherever you like. There is no AU on Windows.

## Documentation

- [Manual](https://github.com/${REPO}/blob/${TAG}/${MANUAL_PATH})
- [Changelog](https://github.com/${REPO}/blob/${TAG}/${CHANGELOG})
- [Product page](${PRODUCT_PAGE})

${PLUGIN} is part of the [Basilica Audio](https://github.com/basilica-audio)
plugin suite.
FOOTER
} > "$BODY"

# ==============================================================================
# 4. Publish.
# ==============================================================================
# Create-or-update rather than create-only: the body is a pure function of the
# tag, the checked-out tree and the attached assets, so re-running the workflow
# (and the second, asset-aware pass) converges instead of conflicting.
if [ "$DRY_RUN" = "true" ]; then
    echo "Dry run - the release for $TAG is left untouched. Body follows."
    cat "$BODY"
elif gh release view "$TAG" -R "$REPO" >/dev/null 2>&1; then
    # Title deliberately left alone on the update path: the body is generated,
    # the title may have been set by hand.
    gh release edit "$TAG" -R "$REPO" --notes-file "$BODY"
    echo "Updated the release notes for $TAG ($(wc -l < "$BODY" | tr -d ' ') lines)."
else
    gh release create "$TAG" -R "$REPO" --title "$TAG" --notes-file "$BODY"
    echo "Created release $TAG with notes from $CHANGELOG ($(wc -l < "$BODY" | tr -d ' ') lines)."
fi

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    {
        printf '### Release body published for `%s`\n\n' "$TAG"
        cat "$BODY"
    } >> "$GITHUB_STEP_SUMMARY"
fi
