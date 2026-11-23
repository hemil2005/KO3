#!/usr/bin/env bash
# Proactively fetch every URL-based third-party archive KOReader's
# build graph references, verify the pinned MD5, then build.
#
# Run this inside WSL from any directory:  bash fix_and_build.sh
#
# Everything it touches lives on the Linux filesystem. Do not move the
# checkout or this script onto /mnt: WSL's 9p client can wedge a build
# process in uninterruptible sleep, and the only recovery is restarting
# WSL.
set -u

# Keep Windows paths out of PATH. They are 9p mounts, and cmake's
# find_program() probes every PATH entry; a stalled 9p lookup hangs the
# build forever. It also stops Windows .exe tools being picked up.
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

cd "$HOME/koreader" || exit 1
builddir="$HOME/koreader/base/build/x86_64-linux-gnu-debug/cmake"
log="$HOME/ao3_base_build.log"

prefetch() {
    local line rest dest md5 url src tmp ok failed=0
    declare -A dest_md5=()
    declare -A dest_urls=()

    # Enumerate every archive the build graph references and the MD5 that
    # KOReader pins for it. ninja prints the full command for each step.
    while IFS= read -r line; do
        case "$line" in
            *download_archive*) ;;
            *) continue ;;
        esac
        rest=${line#*download_archive }
        # shellcheck disable=SC2086
        set -- $rest
        dest=${1:-}
        md5=${2:-}
        [ -n "$dest" ] && [ -n "$md5" ] || continue
        if [ -z "${dest_md5[$dest]:-}" ]; then
            dest_md5[$dest]=$md5
            shift 2
            dest_urls[$dest]="$*"
        fi
    done < <(ninja -C "$builddir" -t commands 2>/dev/null || true)

    echo "known archives: ${#dest_md5[@]}"
    for dest in "${!dest_md5[@]}"; do
        md5=${dest_md5[$dest]}
        if [ -f "$dest" ] && [ "$(md5sum "$dest" | awk '{print $1}')" = "$md5" ]; then
            continue
        fi
        echo "missing: $dest"
        mkdir -p "$(dirname "$dest")"
        ok=0
        for url in ${dest_urls[$dest]}; do
            case "$url" in
                http://*|https://*) ;;
                *) continue ;;
            esac
            for src in \
                "https://ghproxy.net/$url" \
                "https://gh-proxy.com/$url" \
                "https://ghfast.top/$url" \
                "$url"
            do
                tmp="${dest}.download"
                if curl -sS -L --retry 1 --connect-timeout 30 --max-time 900 -o "$tmp" "$src" \
                    && [ "$(md5sum "$tmp" | awk '{print $1}')" = "$md5" ]; then
                    mv "$tmp" "$dest"
                    echo "  fetched $src"
                    ok=1
                    break 2
                fi
            done
            # SDL's GitHub asset is the one host that keeps failing here;
            # libsdl.org serves the identical tarball.
            if [ "$ok" -eq 0 ] && [[ "$url" == *"libsdl-org/SDL"* ]]; then
                src="https://www.libsdl.org/release/$(basename "$url")"
                tmp="${dest}.download"
                if curl -sS -L --connect-timeout 30 --max-time 900 -o "$tmp" "$src" \
                    && [ "$(md5sum "$tmp" | awk '{print $1}')" = "$md5" ]; then
                    mv "$tmp" "$dest"
                    echo "  fetched $src"
                    ok=1
                    break
                fi
            fi
        done
        if [ "$ok" -eq 0 ]; then
            echo "  FAILED: $dest"
            failed=1
        fi
    done
    return "$failed"
}

for i in $(seq 1 20); do
    echo "=== prefetch pass $i ==="
    if ! prefetch; then
        echo "prefetch incomplete"
        exit 1
    fi

    echo "=== build attempt $i ==="
    if make base >"$log" 2>&1; then
        echo "BUILD OK"
        exit 0
    fi
    echo "BUILD FAILED"

    if ! grep -q 'download_archive' "$log"; then
        echo "no download failure found; build failed for another reason"
        tail -60 "$log"
        exit 1
    fi
done

echo "gave up after 20 attempts"
exit 1
