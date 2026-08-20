#!/usr/bin/env bash
# SPDX-License-Identifier: MIT

set -Eeuo pipefail

TAG="${1:-}"
OUTPUT="${2:-}"

[[ "$TAG" =~ ^mesa-[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
  echo "usage: $0 mesa-X.Y.Z [output-file]" >&2
  exit 2
}

VERSION="${TAG#mesa-}"
URL="https://gitlab.freedesktop.org/mesa/mesa/-/raw/$TAG/docs/relnotes/$VERSION.rst"

render_notes() {
  printf '# Mesa %s Turnip changes\n\n' "$VERSION"
  awk '
    /^New features$/ { section = "New features"; next }
    /^Bug fixes$/ { section = "Bug fixes"; next }
    /^Changes$/ { section = "Changes"; next }
    /^[-=]{3,}$/ { next }
    /^- (tu([\/:]|$)|vulkan\/android:)/ {
      if (section != "" && !seen[section]++)
        printf "## %s\n\n", section
      if (section != "")
        print
    }
  '
}

if [[ -n "$OUTPUT" ]]; then
  curl --fail --silent --show-error --location "$URL" | render_notes > "$OUTPUT"
else
  curl --fail --silent --show-error --location "$URL" | render_notes
fi
