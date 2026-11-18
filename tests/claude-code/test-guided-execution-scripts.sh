#!/usr/bin/env bash
# Tests for guided-execution's helpers (skills/guided-execution/scripts/):
# guided-snapshot photographs the working tree as a git tree object without
# touching the index.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GE_SCRIPTS="$REPO_ROOT/skills/guided-execution/scripts"

FAILURES=0
TEST_ROOT=""

pass() { echo "  [PASS] $1"; }
fail() {
    echo "  [FAIL] $1"
    FAILURES=$((FAILURES + 1))
}

cleanup() {
    if [[ -n "$TEST_ROOT" && -d "$TEST_ROOT" ]]; then
        rm -rf "$TEST_ROOT"
    fi
}

main() {
    echo "=== Test: guided-execution scripts ==="

    TEST_ROOT="$(mktemp -d)"
    trap cleanup EXIT

    git init -q -b main "$TEST_ROOT/repo"
    local repo
    repo="$(cd "$TEST_ROOT/repo" && git rev-parse --show-toplevel)"
    # Same spelling as the scripts print: C:/... from cygpath -m on Windows,
    # plain pwd elsewhere.
    repo="$(cd "$repo" && if command -v cygpath >/dev/null 2>&1; then cygpath -m "$PWD"; else pwd; fi)"
    local git_id=(-c user.email=t@example.com -c user.name=t -c commit.gpgsign=false)

    cat > "$repo/plan.md" <<'PLAN'
# Plan

## Task 1: First thing

Do the first thing.

## Task 2: Second thing

Do the second thing.
PLAN
    printf 'ignored.txt\n' > "$repo/.gitignore"
    ( cd "$repo" && git add plan.md .gitignore && git "${git_id[@]}" commit -qm fixture )

    # --- guided-snapshot ---
    local snap head_tree
    snap="$(cd "$repo" && bash "$GE_SCRIPTS/guided-snapshot")"
    head_tree="$(cd "$repo" && git rev-parse 'HEAD^{tree}')"
    if [[ "$snap" == "$head_tree" ]]; then
        pass "guided-snapshot of a clean tree is HEAD's tree"
    else
        fail "guided-snapshot of a clean tree is HEAD's tree (got '$snap', want '$head_tree')"
    fi

    printf 'new\n' > "$repo/new.txt"
    printf 'secret\n' > "$repo/ignored.txt"
    snap="$(cd "$repo" && bash "$GE_SCRIPTS/guided-snapshot")"
    if [[ "$snap" != "$head_tree" ]] && (cd "$repo" && git ls-tree -r --name-only "$snap") | grep -qx 'new.txt'; then
        pass "guided-snapshot includes an untracked file"
    else
        fail "guided-snapshot includes an untracked file (snap=$snap)"
    fi
    if (cd "$repo" && git ls-tree -r --name-only "$snap") | grep -qx 'ignored.txt'; then
        fail "guided-snapshot leaves out ignored files"
    else
        pass "guided-snapshot leaves out ignored files"
    fi

    printf 'staged\n' > "$repo/staged.txt"
    ( cd "$repo" && git add staged.txt )
    local cached_before status_before cached_after status_after
    cached_before="$(cd "$repo" && git diff --cached --name-only)"
    status_before="$(cd "$repo" && git status --porcelain)"
    (cd "$repo" && bash "$GE_SCRIPTS/guided-snapshot") >/dev/null
    cached_after="$(cd "$repo" && git diff --cached --name-only)"
    status_after="$(cd "$repo" && git status --porcelain)"
    if [[ "$cached_before" == "$cached_after" && "$status_before" == "$status_after" ]]; then
        pass "guided-snapshot leaves the index and status untouched"
    else
        fail "guided-snapshot leaves the index and status untouched (before: $status_before / after: $status_after)"
    fi

    local snap_here snap_c
    snap_here="$(cd "$repo" && bash "$GE_SCRIPTS/guided-snapshot")"
    snap_c="$(cd "$TEST_ROOT" && bash "$GE_SCRIPTS/guided-snapshot" -C "$repo")"
    if [[ "$snap_here" == "$snap_c" ]]; then
        pass "guided-snapshot -C DIR from outside the repo gives the same tree"
    else
        fail "guided-snapshot -C DIR from outside the repo gives the same tree ($snap_here vs $snap_c)"
    fi
    # Back to a clean tree for the cases below.
    ( cd "$repo" && git reset -q && rm -f new.txt staged.txt ignored.txt )

    if [[ "$FAILURES" -gt 0 ]]; then
        echo "FAILED: $FAILURES"
        exit 1
    fi
    echo "All guided-execution script tests passed"
}

main "$@"
