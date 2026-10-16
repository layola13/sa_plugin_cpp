#!/bin/sh
# tools/sweep.sh — acceptance sweep for sa_plugin_cpp demos.
#
# For every demos/basic/*/:
#   1. cpp build main.cpp            (C++ -> SA)
#   2. committed main.sa is in sync  (regen with REGEN=1)
#   3. sa check                      (verifier)
#   4. run via BACKEND and diff against expected.stdout
#
# Env:
#   CPP_BIN  cpp binary            (default: <repo>/zig-out/bin/cpp)
#   SA_BIN   sa binary             (default: sibling ../../sci/zig-out/bin/sa)
#   BACKEND  js | exe              (default: js; exe needs an LLVM-built sa)
#   REGEN=1  refresh committed main.sa files instead of checking them
#   SWEEP_WORK  scratch dir        (default: /tmp/opencode/cpp-sweep)
set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CPP_BIN=${CPP_BIN:-"$ROOT/zig-out/bin/cpp"}
SA_BIN=${SA_BIN:-"$ROOT/../sci/zig-out/bin/sa"}
BACKEND=${BACKEND:-js}
WORK=${SWEEP_WORK:-/tmp/opencode/cpp-sweep}
REGEN=${REGEN:-0}

pass=0
fail=0
failed=""

msg() { printf '%s\n' "$*"; }

for d in "$ROOT"/demos/basic/*/; do
    [ -d "$d" ] || continue
    name=$(basename "$d")
    cpp="$d/main.cpp"
    exp="$d/expected.stdout"
    pinned="$d/main.sa"
    [ -f "$cpp" ] || { msg "SKIP $name (no main.cpp)"; continue; }
    [ -f "$exp" ] || { msg "FAIL $name (no expected.stdout)"; fail=$((fail + 1)); failed="$failed $name"; continue; }
    mkdir -p "$WORK/$name"
    fresh="$WORK/$name/main.sa"
    got="$WORK/$name/got.stdout"

    if ! "$CPP_BIN" build "$cpp" --out "$fresh" > "$WORK/$name/build.log" 2>&1; then
        msg "FAIL $name (cpp build)"; tail -n 3 "$WORK/$name/build.log"
        fail=$((fail + 1)); failed="$failed $name"; continue
    fi
    if [ "$REGEN" = "1" ]; then
        cp "$fresh" "$pinned"
    elif [ -f "$pinned" ]; then
        if ! cmp -s "$fresh" "$pinned"; then
            msg "FAIL $name (committed main.sa out of sync; rerun with REGEN=1)"
            fail=$((fail + 1)); failed="$failed $name"; continue
        fi
    else
        msg "FAIL $name (missing committed main.sa; rerun with REGEN=1)"
        fail=$((fail + 1)); failed="$failed $name"; continue
    fi
    if ! "$SA_BIN" check "$fresh" > "$WORK/$name/check.log" 2>&1; then
        msg "FAIL $name (sa check)"; tail -n 3 "$WORK/$name/check.log"
        fail=$((fail + 1)); failed="$failed $name"; continue
    fi
    if [ "$BACKEND" = "exe" ]; then
        if ! "$SA_BIN" build-exe "$fresh" -o "$WORK/$name/demo" > "$WORK/$name/run.log" 2>&1; then
            msg "FAIL $name (sa build-exe)"; tail -n 3 "$WORK/$name/run.log"
            fail=$((fail + 1)); failed="$failed $name"; continue
        fi
        if ! "$WORK/$name/demo" > "$got" 2> "$WORK/$name/run.log"; then
            msg "FAIL $name (native run)"; tail -n 3 "$WORK/$name/run.log"
            fail=$((fail + 1)); failed="$failed $name"; continue
        fi
    else
        if ! "$SA_BIN" build-js "$fresh" -o "$WORK/$name/demo.mjs" > "$WORK/$name/run.log" 2>&1; then
            msg "FAIL $name (sa build-js)"; tail -n 3 "$WORK/$name/run.log"
            fail=$((fail + 1)); failed="$failed $name"; continue
        fi
        if ! node "$WORK/$name/demo.mjs" > "$got" 2> "$WORK/$name/run.log"; then
            msg "FAIL $name (node run)"; tail -n 3 "$WORK/$name/run.log"
            fail=$((fail + 1)); failed="$failed $name"; continue
        fi
    fi
    if ! cmp -s "$exp" "$got"; then
        msg "FAIL $name (output mismatch)"
        diff -u "$exp" "$got" | head -n 10
        fail=$((fail + 1)); failed="$failed $name"; continue
    fi
    msg "ok $name"
    pass=$((pass + 1))
done

msg "----"
msg "pass=$pass fail=$fail backend=$BACKEND"
if [ "$fail" -ne 0 ]; then
    msg "failed:$failed"
    exit 1
fi
