#!/usr/bin/env zsh

# Tests for prompt_impure_async_git_dirty.
#
# The function outputs an oh-my-posh style summary "STAGING|WORKING" where
# STAGING is like "+2 ~1 -1" (added/modified/deleted in the index) and
# WORKING is "*" when the working tree is dirty or empty when it is clean.
# Return code is 0 for a clean repo, 1 for a dirty one.

setopt clobber
set -euo pipefail

zmodload -F zsh/files b:zf_rm b:zf_mkdir

source "${0:A:h}/test-helper.zsh"

tmpdir="$PWD/.ai-temporary/git-dirty-test.$$"
zf_mkdir -p "$tmpdir"

cleanup() {
	zf_rm -rf -- "$tmpdir"
}
trap cleanup EXIT

setup_repo() {
	cd "$tmpdir"
	command git init -q
	command git config user.email "test@test.com"
	command git config user.name "Test"
	echo "initial" > file.txt
	command git add file.txt
	command git commit -q -m "initial"
}

# Run the dirty check. $1 is the untracked_dirty flag (1 = count untracked).
check_dirty() {
	local dirty_output dirty_code
	dirty_output=$(prompt_impure_async_git_dirty "$@") && dirty_code=0 || dirty_code=$?
	typeset -g check_output=$dirty_output check_code=$dirty_code
}

setup_repo

# Clean repo: return 0, no output.
check_dirty 1
assert_equal 0 $check_code "clean repo should return 0"
assert_empty "$check_output" "clean repo should have no output"

# Unstaged modification only: working dirty, no staging.
echo "modified" > file.txt
check_dirty 1
assert_equal 1 $check_code "unstaged change should return 1"
assert_equal "|*" "$check_output" "unstaged change should show empty staging + working marker"

# Staged modification only: staging "~1", clean working tree.
command git add file.txt
check_dirty 1
assert_equal 1 $check_code "staged change should return 1"
assert_equal "~1|" "$check_output" "staged modification should show ~1 with no working marker"

# Staged + unstaged on the same file: staging "~1", working dirty.
echo "more" > file.txt
check_dirty 1
assert_equal 1 $check_code "staged+unstaged should return 1"
assert_equal "~1|*" "$check_output" "staged+unstaged should show ~1 and working marker"
command git checkout -q -- file.txt
command git reset -q HEAD -- file.txt 2>/dev/null || true
command git checkout -q -- file.txt

# Staged addition: staging "+1".
echo "added" > added.txt
command git add added.txt
check_dirty 1
assert_equal 1 $check_code "staged addition should return 1"
assert_equal "+1|" "$check_output" "staged addition should show +1"
command git commit -q -m "add added.txt"

# Staged deletion: staging "-1".
command git rm -q added.txt
check_dirty 1
assert_equal 1 $check_code "staged deletion should return 1"
assert_equal "-1|" "$check_output" "staged deletion should show -1"
command git commit -q -m "remove added.txt"

# Multiple staged kinds: +N ~N together, space separated.
echo "newone" > newone.txt
echo "newtwo" > newtwo.txt
command git add newone.txt newtwo.txt
echo "touch" > file.txt
command git add file.txt
check_dirty 1
assert_equal 1 $check_code "mixed staging should return 1"
assert_equal "+2 ~1|" "$check_output" "mixed staging should show +2 ~1"
command git commit -q -m "mixed"

# Untracked only, counted: working dirty.
echo "untracked" > untracked.txt
check_dirty 1
assert_equal 1 $check_code "untracked should return 1 when counted"
assert_equal "|*" "$check_output" "untracked should show working marker when counted"

# Untracked only, ignored (untracked_dirty=0): clean.
check_dirty 0
assert_equal 0 $check_code "untracked should be clean when ignored"
assert_empty "$check_output" "untracked should produce no output when ignored"
zf_rm -f untracked.txt

print "git-dirty tests passed"
