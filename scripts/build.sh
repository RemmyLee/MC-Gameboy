#!/bin/sh
# Compile MC-Gameboy with Quartus Prime Lite 17.0.2 and stamp the output.
# Usage: scripts/build.sh [YYYYMMDD]
set -eu

cd "$(dirname "$0")/.."
DATE="${1:-$(date +%Y%m%d)}"
QUARTUS="${QUARTUS:-$HOME/intelFPGA_lite/17.0/quartus/bin}"
export PATH="$QUARTUS:$PATH"

UPSTREAM="$(git rev-parse --short HEAD)"
START="$(date +%s)"

# SEED=n picks a fitter seed when a marginal clock misses timing. The qsf
# already carries SEED 1; ours is appended after it and wins. The edit is
# undone by the git checkout below.
if [ -n "${SEED:-}" ]; then
    git checkout Gameboy.qsf
    # the qsf is CRLF with no final newline
    printf '\r\nset_global_assignment -name SEED %s\r\n' "$SEED" >> Gameboy.qsf
fi

quartus_sh --flow compile Gameboy > build.log 2>&1 || {
    echo "build failed, see build.log" >&2
    grep -n "^Error" build.log | head -20 >&2
    exit 1
}

END="$(date +%s)"
mkdir -p out
cp output_files/Gameboy.rbf "out/MC-Gameboy_$DATE.rbf"
{
    echo "MC-Gameboy_$DATE.rbf"
    echo "commit: $UPSTREAM"
    echo "seed: ${SEED:-default}"
    echo "wall: $((END - START)) s"
    echo "critical warnings: $(grep -c "Critical Warning" build.log || true)"
    echo
    cat output_files/Gameboy.fit.summary
    echo
    cat output_files/Gameboy.sta.summary
} > "out/MC-Gameboy_$DATE.txt"

# Quartus rewrites the project file on every run; keep the tree clean.
git checkout Gameboy.qsf

sha256sum "out/MC-Gameboy_$DATE.rbf"
grep -n "Slack" "out/MC-Gameboy_$DATE.txt" | head -3
