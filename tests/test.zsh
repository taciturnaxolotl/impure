#!/usr/bin/env zsh
#
# Run every test file in its own subshell so a failure in one cannot mask
# the others, and report an accurate overall pass/fail. Each test file is
# expected to exit non-zero on failure.

cd -- "${0:A:h}"

local -a test_files
test_files=(*.zsh)

local -a failed
local test_file test_status

for test_file in $test_files; do
	# Skip the harness itself, the shared helper, and the benchmark
	# (the benchmark is a manual performance tool, not a pass/fail test).
	case $test_file in
		test.zsh|test-helper.zsh|benchmark.zsh) continue ;;
	esac

	print -- "Running $test_file"
	zsh "$test_file"
	test_status=$?
	if (( test_status != 0 )); then
		failed+=("$test_file (exit $test_status)")
	fi
done

print --
if (( ${#failed} )); then
	print -u2 -- "FAILED:"
	for test_file in $failed; do
		print -u2 -- "  - $test_file"
	done
	exit 1
fi

print -- "All tests passed."
