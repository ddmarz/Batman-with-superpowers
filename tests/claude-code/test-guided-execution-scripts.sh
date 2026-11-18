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

## Task 3: Third thing

Do the third thing.

## Task 4: Fourth thing

Do the fourth thing.
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

    local ws="$repo/.superpowers/sdd/plan"

    # --- guided-task-start ---
    local rc=0 out
    (cd "$repo" && bash "$GE_SCRIPTS/guided-task-start" plan.md >/dev/null 2>&1) || rc=$?
    if [[ "$rc" -eq 2 ]]; then
        pass "guided-task-start without a task number errors with exit 2"
    else
        fail "guided-task-start without a task number errors with exit 2 (got $rc)"
    fi

    out="$(cd "$repo" && bash "$GE_SCRIPTS/guided-task-start" plan.md 1)"
    if [[ "$out" == *"brief: $ws/task-1-brief.md"* ]] \
        && [[ "$out" =~ base:\ [0-9a-f]{40} ]] \
        && [[ "$out" == *"uncommitted: no"* ]] \
        && [[ "$out" == *"resumed: no"* ]]; then
        pass "guided-task-start prints brief, base, uncommitted: no, resumed: no on a clean tree"
    else
        fail "guided-task-start prints brief, base, uncommitted: no, resumed: no on a clean tree (got: $out)"
    fi
    local start_base="${out#*base: }"
    start_base="${start_base%%$'\n'*}"
    if [[ "$(cd "$repo" && git cat-file -t "$start_base")" == "tree" ]]; then
        pass "guided-task-start's base is a tree object"
    else
        fail "guided-task-start's base is a tree object ($start_base)"
    fi

    if [[ -f "$ws/guided" && "$(cat "$ws/guided")" == "plan.md" && -d "$ws/reports" ]]; then
        pass "guided-task-start creates the guided marker (plan path) and reports/"
    else
        fail "guided-task-start creates the guided marker (plan path) and reports/"
    fi

    # Uncommitted work that no guided task produced (the plan file itself,
    # a stray note) is not "an earlier task is still uncommitted".
    printf 'changed\n' >> "$repo/plan.md"
    printf 'note\n' > "$repo/note.txt"
    out="$(cd "$repo" && bash "$GE_SCRIPTS/guided-task-start" plan.md 3)"
    if [[ "$out" == *"uncommitted: no"* ]]; then
        pass "guided-task-start ignores uncommitted changes no guided task made"
    else
        fail "guided-task-start ignores uncommitted changes no guided task made (got: $out)"
    fi
    ( cd "$repo" && git checkout -q -- plan.md && rm -f note.txt )

    # Starting a task again (after a compaction, in a new session) keeps the
    # first BASE, so work done before the restart stays in the task's diff.
    printf 'half\n' > "$repo/half.txt"
    out="$(cd "$repo" && bash "$GE_SCRIPTS/guided-task-start" plan.md 1)"
    if [[ "$out" == *"base: $start_base"* && "$out" == *"resumed: yes"* ]]; then
        pass "guided-task-start on a started task keeps its BASE and says resumed: yes"
    else
        fail "guided-task-start on a started task keeps its BASE and says resumed: yes (got: $out)"
    fi
    ( cd "$repo" && rm -f half.txt )

    # --- guided-task-done ---
    rc=0
    (cd "$repo" && bash "$GE_SCRIPTS/guided-task-done" plan.md 1 "$start_base" true >/dev/null 2>&1) || rc=$?
    if [[ "$rc" -eq 2 ]]; then
        pass "guided-task-done without -- errors with exit 2"
    else
        fail "guided-task-done without -- errors with exit 2 (got $rc)"
    fi

    local head_commit
    head_commit="$(cd "$repo" && git rev-parse HEAD)"
    rc=0
    (cd "$repo" && bash "$GE_SCRIPTS/guided-task-done" plan.md 1 "$head_commit" -- true >/dev/null 2>&1) || rc=$?
    if [[ "$rc" -eq 2 ]]; then
        pass "guided-task-done rejects a BASE that is not a tree"
    else
        fail "guided-task-done rejects a BASE that is not a tree (got $rc)"
    fi

    rc=0
    (cd "$repo" && bash "$GE_SCRIPTS/guided-task-done" plan.md 1 "$start_base" -- false >/dev/null 2>&1) || rc=$?
    if [[ "$rc" -ne 0 ]] && ! grep -q '^Task 1:' "$ws/progress.md" 2>/dev/null; then
        pass "guided-task-done records nothing when the tests fail"
    else
        fail "guided-task-done records nothing when the tests fail (rc=$rc)"
    fi

    printf 'added\n' > "$repo/added.txt"
    out="$(cd "$repo" && bash "$GE_SCRIPTS/guided-task-done" plan.md 1 "$start_base" -- true)"
    if grep -q '^Task 1: complete (guided, uncommitted, trees ' "$ws/progress.md"; then
        pass "guided-task-done appends a guided completion line to the ledger"
    else
        fail "guided-task-done appends a guided completion line to the ledger"
    fi
    if grep -q 'added.txt' "$ws/task-1.diff" 2>/dev/null; then
        pass "guided-task-done saves the task's diff, new files included"
    else
        fail "guided-task-done saves the task's diff, new files included"
    fi
    if [[ "$out" == *added.txt* && "$out" == *"diff: $ws/task-1.diff"* \
        && "$out" == *"report: $ws/reports/task-01.md"* ]]; then
        pass "guided-task-done prints the stat, the diff path and the report path"
    else
        fail "guided-task-done prints the stat, the diff path and the report path (got: $out)"
    fi

    # A change the partner asks for after the report: closing the task again
    # with the same BASE refreshes its diff and keeps one ledger line.
    printf 'tweak\n' > "$repo/tweak.txt"
    (cd "$repo" && bash "$GE_SCRIPTS/guided-task-done" plan.md 1 "$start_base" -- true) >/dev/null
    if grep -q 'tweak.txt' "$ws/task-1.diff" && grep -q 'added.txt' "$ws/task-1.diff"; then
        pass "closing a task again refreshes its diff"
    else
        fail "closing a task again refreshes its diff"
    fi
    if [[ "$(grep -c '^Task 1: complete' "$ws/progress.md")" -eq 1 ]]; then
        pass "closing a task again keeps a single ledger line for it"
    else
        fail "closing a task again keeps a single ledger line for it ($(grep -c '^Task 1: complete' "$ws/progress.md") lines)"
    fi

    # Task 2 starts with Task 1's work still uncommitted: it says so, and its
    # diff is its own.
    out="$(cd "$repo" && bash "$GE_SCRIPTS/guided-task-start" plan.md 2)"
    if [[ "$out" == *"uncommitted: yes"* ]]; then
        pass "guided-task-start reports an earlier guided task's uncommitted work"
    else
        fail "guided-task-start reports an earlier guided task's uncommitted work (got: $out)"
    fi
    local base2="${out#*base: }"
    base2="${base2%%$'\n'*}"
    printf 'second\n' > "$repo/second.txt"
    (cd "$repo" && bash "$GE_SCRIPTS/guided-task-done" plan.md 2 "$base2" -- true) >/dev/null
    if grep -q 'second.txt' "$ws/task-2.diff" && ! grep -q 'added.txt' "$ws/task-2.diff"; then
        pass "a task's diff leaves out earlier uncommitted tasks"
    else
        fail "a task's diff leaves out earlier uncommitted tasks"
    fi

    # The partner commits; the next task no longer reports uncommitted work.
    ( cd "$repo" && git add added.txt tweak.txt second.txt && git "${git_id[@]}" commit -qm "tasks 1-2" )
    out="$(cd "$repo" && bash "$GE_SCRIPTS/guided-task-start" plan.md 4)"
    if [[ "$out" == *"uncommitted: no"* ]]; then
        pass "after the partner commits, guided-task-start says uncommitted: no"
    else
        fail "after the partner commits, guided-task-start says uncommitted: no (got: $out)"
    fi

    # --- guided-off, and the commit guard following the marker ---
    local guard="$REPO_ROOT/hooks/guided-commit-guard"
    local hook_input="{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git commit -m x\"},\"cwd\":\"$repo\"}"
    if [[ "$(printf '%s' "$hook_input" | bash "$guard")" == *'"permissionDecision":"deny"'* ]]; then
        pass "with guided mode on, the commit guard denies git commit in the repo"
    else
        fail "with guided mode on, the commit guard denies git commit in the repo"
    fi

    out="$(cd "$repo" && bash "$GE_SCRIPTS/guided-off" plan.md)"
    if [[ "$out" == "guided: off" && ! -e "$ws/guided" ]]; then
        pass "guided-off removes the marker and prints guided: off"
    else
        fail "guided-off removes the marker and prints guided: off (got: $out)"
    fi

    if [[ -z "$(printf '%s' "$hook_input" | bash "$guard")" ]]; then
        pass "after guided-off, the commit guard allows git commit"
    else
        fail "after guided-off, the commit guard allows git commit"
    fi

    rc=0
    out="$(cd "$repo" && bash "$GE_SCRIPTS/guided-off" plan.md)" || rc=$?
    if [[ "$rc" -eq 0 && "$out" == "guided: off" ]]; then
        pass "guided-off is idempotent"
    else
        fail "guided-off is idempotent (rc=$rc, out=$out)"
    fi

    if [[ "$FAILURES" -gt 0 ]]; then
        echo "FAILED: $FAILURES"
        exit 1
    fi
    echo "All guided-execution script tests passed"
}

main "$@"
