#!/bin/bash
# Runs shellcheck over every shell file in the repository (default severity: style).
. /src/tests/lib/assert.sh >/dev/null
T_NAME=shellcheck
cd /src || exit 1
mapfile -t files < <(grep -rlE '^#!/bin/(ba)?sh|^# shellcheck shell=bash' --include='*' box source image tests attack 2>/dev/null | grep -v '\.py$' | sort)
out=$(shellcheck -x -S style "${files[@]}" 2>&1)
eq "shellcheck clean (${#files[@]} files)" "" "$out"
[ -z "$out" ] || printf '%s\n' "$out" | head -60
done_testing
