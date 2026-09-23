# Shared helpers for MiliControl's release scripts. Source, don't run.

REPO="MiliIdea/MiliControl"
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="$(cd "$SCRIPTS_DIR/.." && pwd)"
INFO_PLIST="$ROOT/MiliControl/Resources/Info.plist"

bold()  { printf "\033[1m%s\033[0m\n" "$*"; }
step()  { printf "\n\033[1;34m▸ %s\033[0m\n" "$*"; }
ok()    { printf "  \033[32m✓\033[0m %s\n" "$*"; }
warn()  { printf "  \033[33m!\033[0m %s\n" "$*"; }
fail()  { printf "\n\033[1;31m✗ %s\033[0m\n" "$*" >&2; exit 1; }

plist_value() {  # plist_value <plist> <key>  → prints the value, or nothing
    /usr/libexec/PlistBuddy -c "Print :$2" "$1" 2>/dev/null || true
}

# Prints the folder holding Sparkle's command-line tools (generate_keys,
# sign_update), downloading the official release once into ~/Library/Caches.
# Pin a version with SPARKLE_VERSION=2.x.y; default: latest release.
sparkle_tools() {
    local version="${SPARKLE_VERSION:-}"
    if [[ -z "$version" ]]; then
        version="$(curl -fsSLI -o /dev/null -w '%{url_effective}' \
            https://github.com/sparkle-project/Sparkle/releases/latest | sed 's:.*/::')"
        [[ -n "$version" && "$version" != "latest" ]] || fail "Couldn't look up the latest Sparkle version (offline?)."
    fi
    local dir="$HOME/Library/Caches/MiliControl-release/Sparkle-$version"
    if [[ ! -x "$dir/bin/sign_update" ]]; then
        mkdir -p "$dir"
        local archive="$dir/Sparkle-$version.tar.xz"
        curl -fsSL -o "$archive" \
            "https://github.com/sparkle-project/Sparkle/releases/download/$version/Sparkle-$version.tar.xz" \
            || fail "Couldn't download Sparkle $version tools."
        tar -xf "$archive" -C "$dir" && rm -f "$archive"
        [[ -x "$dir/bin/sign_update" ]] || fail "Sparkle $version archive has no bin/sign_update."
    fi
    printf "%s/bin" "$dir"
}
