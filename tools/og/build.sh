#!/usr/bin/env bash
# Build patched OpenGFW without running it or changing a router/service.
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: bash tools/og/build.sh [--test] [--output PATH]
       bash tools/og/build.sh --prepare NEW_DIRECTORY

Requires Bash, Go 1.26.4, Git, and standard cp/chmod/mktemp/mv tools.
Downloads pinned source modules through proxy.golang.org and verifies the cache.
Builds linux/arm64 (CGO disabled). Default output: tools/og/build/og-linux-arm64
(relative to this repository; the default build directory is created if needed).
--test      Run the directed engine tests and reassembly tests first (Linux only).
--prepare   Export both patched source trees without compiling or running tests.
            The destination must not exist; its parent must already exist.
--output    Atomically replace only this output file after a successful build.
            No installation, process start, or firewall changes are performed.
EOF
}

die() { printf 'build.sh: %s\n' "$*" >&2; exit 1; }

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
output="$script_dir/build/og-linux-arm64"
output_set=0
prepare=''
run_tests=0
while (($#)); do
    case "$1" in
        --output|-o)
            (($# >= 2)) || die "$1 requires a path"
            [[ -n "$2" ]] || die "$1 requires a nonempty path"
            output=$2; output_set=1; shift 2 ;;
        --prepare)
            (($# >= 2)) || die '--prepare requires a path'
            [[ -n "$2" ]] || die '--prepare requires a nonempty path'
            prepare=$2; shift 2 ;;
        --test) run_tests=1; shift ;;
        --help|-h) usage; exit 0 ;;
        *) die "unknown argument: $1 (see --help)" ;;
    esac
done
[[ -z "$prepare" || ( $output_set == 0 && $run_tests == 0 ) ]] ||
    die '--prepare cannot be combined with --output or --test'

for tool in go git cp chmod mktemp mkdir mv rm dirname basename; do
    command -v "$tool" >/dev/null 2>&1 || die "required tool not found: $tool"
done
# Ignore user Go configuration/workspaces and disallow implicit toolchain updates.
export GOTOOLCHAIN=local GOENV=off GOWORK=off GOFLAGS='' GOEXPERIMENT=''
export GOPROXY=https://proxy.golang.org GOSUMDB=sum.golang.org
export GOPRIVATE='' GONOPROXY='' GONOSUMDB=''
[[ "$(go env GOVERSION)" == go1.26.4 ]] || die 'Go 1.26.4 is required (no toolchain is installed automatically)'
host_os=$(go env GOHOSTOS)
if [[ "$host_os" == windows ]]; then
    command -v cygpath >/dev/null 2>&1 || die 'Windows builds require Git Bash with cygpath'
fi
((run_tests == 0)) || [[ "$host_os" == linux ]] ||
    die '--test requires a Linux Go host; use --prepare and run tests on Linux'

shell_path() {
    if [[ "$host_os" == windows ]]; then cygpath -u "$1"; else printf '%s\n' "$1"; fi
}
if [[ -n "$prepare" ]]; then
    prepare=$(shell_path "$prepare")
    [[ ! -e "$prepare" && ! -L "$prepare" ]] || die '--prepare destination already exists'
    [[ -d "$(dirname -- "$prepare")" ]] || die '--prepare parent directory does not exist'
    prepare="$(cd -- "$(dirname -- "$prepare")" && pwd -P)/$(basename -- "$prepare")"
else
    output=$(shell_path "$output")
    if ((output_set == 0)); then mkdir -p -- "$script_dir/build"; fi
    [[ -d "$(dirname -- "$output")" ]] || die 'output parent directory does not exist'
    output="$(cd -- "$(dirname -- "$output")" && pwd -P)/$(basename -- "$output")"
    [[ ! -L "$output" && ( ! -e "$output" || -f "$output" ) ]] ||
        die 'output must be a regular file path, not a directory, symlink, or special file'
fi
for name in opengfw gopacket; do
    [[ -r "$script_dir/patches/$name.patch" ]] || die "missing patches/$name.patch"
done

scratch_parent=$(cd -- "${TMPDIR:-/tmp}" && pwd -P)
scratch=$(mktemp -d "$scratch_parent/one-openwrt-og.XXXXXXXX")
scratch=$(cd -- "$scratch" && pwd -P)
staged_output=''
cleanup() {
    [[ -z "$staged_output" ]] || rm -f -- "$staged_output"
    if [[ -e "$scratch" || -L "$scratch" ]]; then
        local resolved_scratch
        resolved_scratch=$(cd -- "$scratch" && pwd -P) || {
            printf 'build.sh: refusing cleanup of unresolved scratch path: %s\n' "$scratch" >&2
            return 1
        }
        if [[ "$resolved_scratch" == "$scratch" &&
              "${resolved_scratch%/*}" == "$scratch_parent" &&
              "${resolved_scratch##*/}" == one-openwrt-og.???????? ]]; then
            rm -rf -- "$resolved_scratch"
        else
            printf 'build.sh: refusing cleanup outside the created scratch directory: %s\n' "$resolved_scratch" >&2
            return 1
        fi
    fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir "$scratch/download" "$scratch/sources"
# An explicit temporary Git work tree avoids inheriting a repository from TMPDIR.
git init --quiet "$scratch/patch-check"
cat > "$scratch/download/go.mod" <<'EOF'
module one-openwrt-og-build

go 1.21

require (
    github.com/apernet/OpenGFW v0.3.2
    github.com/google/gopacket v1.1.20-0.20220810144506-32ee38206866
)
EOF
opengfw_module=github.com/apernet/OpenGFW@v0.3.2
gopacket_module=github.com/google/gopacket@v1.1.20-0.20220810144506-32ee38206866
(
    cd "$scratch/download"
    go mod download "$opengfw_module" "$gopacket_module"
    go mod verify
)
for name in opengfw gopacket; do
    if [[ "$name" == opengfw ]]; then module=$opengfw_module; else module=$gopacket_module; fi
    cache_dir=$(cd "$scratch/download" && go list -m -f '{{.Dir}}' "$module")
    cache_dir=${cache_dir//$'\r'/}
    cache_dir=$(shell_path "$cache_dir")
    [[ -d "$cache_dir" ]] || die "missing downloaded module directory: $module"
    cp -R -- "$cache_dir" "$scratch/sources/$name"
    chmod -R u+w "$scratch/sources/$name"
    (
        cd "$scratch/sources/$name"
        git --git-dir="$scratch/patch-check/.git" --work-tree="$scratch/sources/$name" apply --check "$script_dir/patches/$name.patch"
        git --git-dir="$scratch/patch-check/.git" --work-tree="$scratch/sources/$name" apply "$script_dir/patches/$name.patch"
    )
done

if [[ -n "$prepare" ]]; then
    # mkdir refuses an existing destination, including one created after preflight.
    mkdir -- "$prepare"
    cp -R -- "$scratch/sources/." "$prepare/"
    printf 'Patched source trees: %s/{opengfw,gopacket}\n' "$prepare"
    exit 0
fi
if ((run_tests)); then
    (cd "$scratch/sources/opengfw" && CGO_ENABLED=0 GOOS=linux GOARCH="$(go env GOHOSTARCH)" go test -mod=readonly ./engine -run '^TestCandidate' -count=1)
    (cd "$scratch/sources/gopacket" && CGO_ENABLED=0 GOOS=linux GOARCH="$(go env GOHOSTARCH)" go test -mod=readonly ./reassembly -count=1)
fi
staged_output=$(mktemp "$(dirname -- "$output")/.og-build.XXXXXXXX")
(
    cd "$scratch/sources/opengfw"
    CGO_ENABLED=0 GOOS=linux GOARCH=arm64 GOARM64=v8.0 go build -mod=readonly -trimpath -buildvcs=false -o "$staged_output" .
)
chmod 0755 "$staged_output"
mv -f -- "$staged_output" "$output"
staged_output=''
printf 'Built linux/arm64 binary: %s\n' "$output"
