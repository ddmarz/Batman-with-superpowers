#!/usr/bin/env bash
# Tests for hooks/guided-commit-guard: the PreToolUse hook that denies the
# agent's `git commit` while guided execution is active, i.e. while a
# .superpowers/sdd/<plan>/guided marker exists above the command's cwd.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GUARD="$REPO_ROOT/hooks/guided-commit-guard"
HOOKS_JSON="$REPO_ROOT/hooks/hooks.json"

FAILURES=0
TEST_ROOT="$(mktemp -d)"
cleanup() { rm -rf "$TEST_ROOT"; }
trap cleanup EXIT

pass() { echo "  [PASS] $1"; }
fail() { echo "  [FAIL] $1"; FAILURES=$((FAILURES + 1)); }

# JSON-escape a string the way Claude Code's hook input does.
json_str() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    printf '"%s"' "$s"
}

# run_guard TOOL COMMAND CWD -> sets OUT and RC
run_guard() {
    local input
    input="{\"session_id\":\"s\",\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"$1\",\"tool_input\":{\"command\":$(json_str "$2"),\"description\":\"x\"},\"cwd\":$(json_str "$3")}"
    RC=0
    OUT="$(printf '%s' "$input" | bash "$GUARD" 2>/dev/null)" || RC=$?
}

expect_deny() {
    local desc="$1"
    shift
    run_guard "$@"
    if [[ "$RC" -eq 0 && "$OUT" == *'"permissionDecision":"deny"'* ]]; then
        pass "$desc"
    else
        fail "$desc (rc=$RC, out=$OUT)"
    fi
}

expect_allow() {
    local desc="$1"
    shift
    run_guard "$@"
    if [[ "$RC" -eq 0 && -z "$OUT" ]]; then
        pass "$desc"
    else
        fail "$desc (rc=$RC, out=$OUT)"
    fi
}

echo "=== Test: guided-commit-guard ==="

plain="$TEST_ROOT/plain"
guided="$TEST_ROOT/guided"
outside="$TEST_ROOT/outside"
mkdir -p "$plain/.superpowers/sdd/plan" "$guided/.superpowers/sdd/plan" "$guided/src" "$outside"
printf 'docs/plans/my-plan.md\n' > "$guided/.superpowers/sdd/plan/guided"

expect_allow "no marker: commit allowed" Bash 'git commit -m x' "$plain"
expect_deny "marker: plain commit denied" Bash 'git commit -m x' "$guided"
expect_deny "marker: PowerShell commit denied" PowerShell 'git commit -m x' "$guided"
expect_deny "marker: git -C dir commit denied" Bash 'git -C sub commit -m x' "$guided"
expect_deny "marker: git -c k=v commit denied" Bash 'git -c user.name=a commit' "$guided"
expect_deny "marker: chained add && commit denied" Bash 'git add . && git commit -m x' "$guided"
expect_deny "marker: commit from a subdirectory denied" Bash 'git commit -m x' "$guided/src"

if command -v cygpath >/dev/null 2>&1; then
    expect_deny "marker: Windows-style cwd denied" Bash 'git commit -m x' "$(cygpath -w "$guided")"
else
    echo "  [SKIP] Windows-style cwd (no cygpath)"
fi

expect_allow "marker: git log --grep commit allowed" Bash 'git log --grep commit' "$guided"
expect_allow "marker: echo commit allowed" Bash 'echo commit' "$guided"
expect_allow "marker: git status allowed" Bash 'git status' "$guided"
expect_allow "outside the repo: commit allowed" Bash 'git commit -m x' "$outside"

# A nested working tree (a git worktree has a .git *file*) is another
# checkout: the guided marker above it is not its business.
mkdir -p "$guided/.worktrees/other/src"
printf 'gitdir: /somewhere/.git/worktrees/other\n' > "$guided/.worktrees/other/.git"
expect_allow "nested worktree under a guided checkout: commit allowed" Bash 'git commit -m x' "$guided/.worktrees/other/src"

run_guard Bash 'git commit -m x' "$guided"
if [[ "$OUT" == *guided-execution* && "$OUT" == *docs/plans/my-plan.md* ]]; then
    pass "deny reason names guided-execution and the plan"
else
    fail "deny reason names guided-execution and the plan (out=$OUT)"
fi

if grep -q '"PreToolUse"' "$HOOKS_JSON" && grep -q '"Bash|PowerShell"' "$HOOKS_JSON" \
    && grep -q 'guided-commit-guard' "$HOOKS_JSON"; then
    pass "hooks.json registers the guard on Bash|PowerShell"
else
    fail "hooks.json registers the guard on Bash|PowerShell"
fi

if [[ "$FAILURES" -gt 0 ]]; then
    echo "FAILED: $FAILURES"
    exit 1
fi
echo "All guided-commit-guard tests passed"
