#!/usr/bin/env zsh

source "${0:A:h}/test-helper.zsh"
set +e
zmodload -F zsh/files b:zf_rm b:zf_mkdir

main() {
	test_no_infinite_recursion_on_worker_failure || return
	test_worker_startup_failure_clears_git_state || return
	test_leaving_working_tree_clears_stale_git_state || return
	test_worker_sync_is_assumed_and_jobs_queue_immediately || return
	test_worker_sync_cd_failure_forgets_sync || return
	test_worker_sync_enqueue_failure_is_not_recorded || return
	test_jj_result_older_than_latest_request_is_requeued || return
	test_async_eval_setup_failure_reports_callback || return
	test_real_worker_sync_reports_encoded_status || return
	test_callback_no_recursion_on_worker_failure || return
	test_callback_failed_recovery_clears_git_state || return
	test_callback_recovery_calls_tasks_on_success || return
	test_dead_worker_no_stderr_leakage || return

	print -- "async-worker-failure tests passed"
}

assert_git_state_empty() {
	local message=$1

	assert_empty "${prompt_impure_vcs_info[branch]-}" "branch should be cleared $message" || return
	assert_empty "${prompt_impure_vcs_info[top]-}" "top-level should be cleared $message" || return
	assert_empty "${prompt_impure_vcs_info[action]-}" "action should be cleared $message" || return
	assert_empty "${prompt_impure_vcs_info[pwd]-}" "pwd should be cleared $message" || return
	assert_empty "${prompt_impure_git_dirty-}" "dirty marker should be cleared $message" || return
	assert_empty "${prompt_impure_git_arrows-}" "arrows should be cleared $message" || return
	assert_empty "${prompt_impure_git_fetch_pattern-}" "fetch pattern should be cleared $message" || return
}

test_no_infinite_recursion_on_worker_failure() {
	# Simulate async_start_worker always failing (e.g. zpty permission denied).
	async_start_worker() { return 1 }

	typeset -g prompt_impure_async_inited=0

	# This should return 1 (failure), not infinitely recurse.
	local ret=0
	prompt_impure_async_init || ret=$?

	assert_equal 1 $ret "prompt_impure_async_init should return 1 when worker fails to start" || return
	assert_equal 0 $prompt_impure_async_inited "prompt_impure_async_inited should be reset to 0 on failure" || return

	unfunction async_start_worker
}

test_worker_startup_failure_clears_git_state() {
	# Simulate async_start_worker failing after Git state was previously populated.
	async_start_worker() {
		return 1
	}

	typeset -gA prompt_impure_vcs_info=(branch main top /tmp/repo action rebase pwd /tmp/repo)
	typeset -g prompt_impure_git_dirty="*"
	typeset -g prompt_impure_git_arrows="⇡"
	typeset -g prompt_impure_git_fetch_pattern="pull|fetch"
	typeset -g prompt_impure_async_inited=0

	prompt_impure_async_git_tasks || :

	assert_git_state_empty "when worker fails to start" || return

	unfunction async_start_worker
}

test_leaving_working_tree_clears_stale_git_state() {
	local saved_pwd=$PWD
	local tmpdir=$PWD/.ai-temporary/worker-sync-clear-$$
	zf_mkdir -p "$tmpdir"

	async_worker_eval() { return 0 }
	async_flush_jobs() { return 0 }
	async_job() { return 1 }

	typeset -g prompt_impure_async_inited=1
	typeset -gA prompt_impure_worker_env=(pwd /tmp/repo git_dir __unset__ git_work_tree __unset__)
	typeset -gA prompt_impure_vcs_info=(branch main top /tmp/repo action rebase pwd /tmp/repo)
	typeset -g prompt_impure_git_dirty="*"
	typeset -g prompt_impure_git_arrows="⇡"
	typeset -g prompt_impure_git_fetch_pattern="pull|fetch"

	builtin cd -q "$tmpdir"

	prompt_impure_async_git_tasks || :

	builtin cd -q "$saved_pwd"
	zf_rm -rf -- "$saved_pwd/.ai-temporary"

	assert_git_state_empty "after leaving the working tree" || return

	unfunction async_worker_eval async_flush_jobs async_job
}

test_worker_sync_is_assumed_and_jobs_queue_immediately() {
	local -a worker_eval_command
	local flush_calls=0 eval_calls=0
	local -a queued
	async_worker_eval() {
		local worker=$1; shift
		worker_eval_command=("$@")
		(( eval_calls++ ))
		return 0
	}
	async_flush_jobs() { (( flush_calls++ )); return 0 }
	async_job() { queued+=($2); return 0 }

	typeset -g prompt_impure_async_inited=1
	typeset -gA prompt_impure_worker_env=()
	typeset -gA prompt_impure_vcs_info=(branch "" top "" action "" pwd "")

	prompt_impure_async_git_tasks || :

	assert_equal "$PWD" "${prompt_impure_worker_env[pwd]-}" "worker sync should be recorded when sent, not when answered" || return
	assert_equal 1 $flush_calls "old jobs should be flushed before the worker moves" || return
	assert_equal prompt_impure_async_worker_sync "${worker_eval_command[1]-}" "worker should be sent the sync eval" || return
	assert_equal prompt_impure_async_vcs_info "${queued[1]-}" "git jobs should queue right behind the sync" || return

	# A later prompt in the same directory must not flush or resync, and a
	# reply that never arrives (swallowed by a flush) must not matter.
	queued=()
	prompt_impure_async_git_tasks || :

	assert_equal 1 $flush_calls "an unchanged directory should not flush the worker" || return
	assert_equal 1 $eval_calls "an unchanged directory should not resync the worker" || return
	assert_equal prompt_impure_async_vcs_info "${queued[1]-}" "git jobs should keep queueing without a sync reply" || return

	# An unrelated eval reply (renice) changes nothing.
	prompt_impure_async_callback '[async/eval]' 0 "renice output" 0 "" 0
	assert_equal "$PWD" "${prompt_impure_worker_env[pwd]-}" "unrelated eval callback should keep the sync" || return

	unfunction async_worker_eval async_flush_jobs async_job
}

test_worker_sync_cd_failure_forgets_sync() {
	local saved_pwd=$PWD
	local tmpdir=$PWD/.ai-temporary/worker-sync-$$
	zf_mkdir -p "$tmpdir"
	local -a worker_eval_command
	local render_called=0

	async_worker_eval() {
		local worker=$1; shift
		worker_eval_command=("$@")
		return 0
	}
	async_flush_jobs() { return 0 }
	async_job() { return 0 }
	prompt_impure_preprompt_render() { render_called=1 }

	typeset -g prompt_impure_async_inited=1
	typeset -gA prompt_impure_worker_env=()

	builtin cd -q "$tmpdir"
	zf_rm -rf -- "$tmpdir"

	prompt_impure_async_git_tasks || :

	local sync_output
	sync_output=$("${(@)worker_eval_command}" 2>&1)
	builtin cd -q "$saved_pwd"
	zf_rm -rf -- "$saved_pwd/.ai-temporary"

	# A failure for a superseded sync is ignored.
	typeset -g prompt_impure_jj_bookmark=main
	(( prompt_impure_worker_sync_token++ ))
	typeset -gA prompt_impure_worker_env=(pwd "$PWD" git_dir __unset__ git_work_tree __unset__)
	prompt_impure_async_callback '[async/eval]' 0 "$sync_output" 0 "" 0
	assert_equal "$PWD" "${prompt_impure_worker_env[pwd]-}" "an old sync failure should not undo a newer sync" || return
	assert_equal main "$prompt_impure_jj_bookmark" "an old sync failure should not clear jj state" || return
	(( prompt_impure_worker_sync_token-- ))

	prompt_impure_async_callback '[async/eval]' 0 "$sync_output" 0 "" 1

	assert_empty "${prompt_impure_worker_env[pwd]-}" "failed worker cd should be forgotten so the next prompt retries" || return
	assert_empty "$prompt_impure_jj_bookmark" "failed worker cd should clear jj state" || return
	assert_equal 1 $render_called "failed worker sync should render even when results are pending" || return

	prompt_impure_async_callback prompt_impure_async_vcs_info 0 "pwd ${(q)PWD} branch stale top /tmp/repo action rebase" 0 "" 0

	assert_empty "${prompt_impure_vcs_info[branch]-}" "stale vcs info should not repopulate branch after failed worker sync" || return
	assert_empty "${prompt_impure_vcs_info[top]-}" "stale vcs info should not repopulate top-level after failed worker sync" || return

	prompt_impure_preprompt_render() { : }
	unfunction async_worker_eval async_flush_jobs async_job
}

test_worker_sync_enqueue_failure_is_not_recorded() {
	async_worker_eval() { return 1 }
	async_flush_jobs() { return 0 }
	local job_called=0
	async_job() { job_called=1; return 0 }

	typeset -g prompt_impure_async_inited=1
	typeset -gA prompt_impure_worker_env=()
	typeset -gA prompt_impure_vcs_info=(branch main top /tmp/repo action "" pwd /tmp/repo)

	prompt_impure_async_git_tasks || :

	assert_empty "${prompt_impure_worker_env[pwd]-}" "a sync that never reached the worker should not be recorded" || return
	assert_equal 0 $job_called "no git job should run in an unsynced worker" || return
	assert_git_state_empty "when the worker sync cannot be sent" || return

	unfunction async_worker_eval async_flush_jobs async_job
}

test_jj_result_older_than_latest_request_is_requeued() {
	local -a queued
	async_job() { queued+=("$2 $3"); return 0 }

	typeset -gA prompt_impure_worker_env=(pwd "$PWD" git_dir __unset__ git_work_tree __unset__)
	typeset -g prompt_impure_jj_generation=5
	typeset -g prompt_impure_jj_bookmark=old prompt_impure_jj_changeid=aa

	prompt_impure_async_callback prompt_impure_async_jj_status 0 $'4\nnew|bb|0' 0 "" 0

	assert_equal old "$prompt_impure_jj_bookmark" "a result from a dropped-over request should not render" || return
	assert_equal "prompt_impure_async_jj_status 5" "${queued[1]-}" "a stale jj result should requeue the latest generation" || return

	queued=()
	prompt_impure_async_callback prompt_impure_async_jj_status 0 $'5\nnew|bb|2 ~3' 0 "" 0

	assert_equal 0 ${#queued} "a current jj result should not requeue" || return
	assert_equal new "$prompt_impure_jj_bookmark" "current jj result should set bookmark" || return
	assert_equal bb "$prompt_impure_jj_changeid" "current jj result should set change id" || return
	assert_equal "!2" "$prompt_impure_jj_conflicted" "current jj result should set conflicts" || return
	assert_equal "~3" "$prompt_impure_jj_working" "current jj result should set working copy count" || return

	prompt_impure_async_callback prompt_impure_async_jj_status 1 '5' 0 "" 0
	assert_empty "$prompt_impure_jj_changeid" "leaving a jj repo should clear the change id" || return

	unfunction async_job
}

test_async_eval_setup_failure_reports_callback() {
	typeset -g ASYNC_INIT_DONE=0
	source ./async.zsh

	local callback_job callback_code
	local original_tmpdir=${TMPDIR-}
	local missing_tmpdir=$PWD/.ai-temporary/missing-tmpdir-$$
	zf_rm -rf -- "$missing_tmpdir"

	typeset -g TMPDIR=$missing_tmpdir

	_async_job() {
		local jobname=${ASYNC_JOB_NAME:-$1}
		callback_job=$jobname
		callback_code=1
	}

	_async_eval "print -r -- unreachable"

	if [[ -n $original_tmpdir ]]; then
		typeset -g TMPDIR=$original_tmpdir
	else
		unset TMPDIR
	fi

	assert_equal "[async/eval]" "$callback_job" "async eval setup failure should report through async/eval" || return
	assert_equal 1 "$callback_code" "async eval setup failure should report failure status" || return

	unfunction _async_job
}

test_real_worker_sync_reports_encoded_status() {
	typeset -g ASYNC_INIT_DONE=0
	source ./async.zsh
	typeset -gA ASYNC_PTYS=()
	typeset -gA ASYNC_CALLBACKS=()
	typeset -gA ASYNC_PROCESS_BUFFER=()

	local worker=prompt_impure_worker_sync_test
	async_stop_worker $worker >/dev/null 2>&1 || :
	async_start_worker $worker -u || return

	local saved_pwd=$PWD
	local tmpdir=$PWD/.ai-temporary/worker-sync-real-$$
	zf_mkdir -p "$tmpdir"
	zf_rm -rf -- "$tmpdir"

	local callback_job callback_code callback_output
	real_worker_callback() {
		callback_job=$1
		callback_code=$2
		callback_output=$3
	}

	async_worker_eval $worker prompt_impure_async_worker_sync 1 "$tmpdir" 0 "" 0 "" || return

	local index
	for index in {1..50}; do
		async_process_results $worker real_worker_callback direct >/dev/null 2>&1
		[[ $callback_job == '[async/eval]' ]] && break
		sleep 0.01
	done

	async_stop_worker $worker >/dev/null 2>&1 || :
	builtin cd -q "$saved_pwd"

	assert_equal "[async/eval]" "$callback_job" "real worker sync should report through async/eval" || return
	assert_equal 1 "$callback_code" "real async/eval wrapper should preserve eval status" || return

	if [[ $callback_output != *"prompt_impure_worker_sync:1:1"* ]]; then
		print -u2 -- "Assertion failed: real worker sync should encode failed cd status in output"
		print -u2 -- "Actual: $callback_output"
		return 1
	fi

	unfunction real_worker_callback
}

test_callback_no_recursion_on_worker_failure() {
	# Simulate async_start_worker always failing.
	async_start_worker() { return 1 }
	async_stop_worker() { : }

	# Stub prompt_impure_vcs_tasks to detect if it gets called.
	local tasks_called=0
	prompt_impure_vcs_tasks() { tasks_called=1 }

	typeset -g prompt_impure_async_inited=0

	# Simulate the callback receiving an async worker crash (code 3).
	# Code 3 is representative; codes 2 and 130 share the same branch.
	prompt_impure_async_callback '[async]' 3 '' 0 'worker crashed' 0

	assert_equal 0 $prompt_impure_async_inited "prompt_impure_async_inited should remain 0 after failed recovery" || return
	assert_equal 0 $tasks_called "prompt_impure_vcs_tasks should not be called when recovery fails" || return

	unfunction async_start_worker async_stop_worker prompt_impure_vcs_tasks
}

test_callback_failed_recovery_clears_git_state() {
	# Simulate async_start_worker failing after Git state was previously populated.
	async_start_worker() {
		return 1
	}
	async_stop_worker() {
		:
	}

	typeset -gA prompt_impure_vcs_info=(branch main top /tmp/repo action rebase pwd /tmp/repo)
	typeset -g prompt_impure_git_dirty="*"
	typeset -g prompt_impure_git_arrows="⇡"
	typeset -g prompt_impure_git_fetch_pattern="pull|fetch"
	typeset -g prompt_impure_async_inited=1
	local render_called=0
	prompt_impure_preprompt_render() {
		render_called=1
	}

	# Use next_pending=1 because a worker crash may be reported while buffered output remains.
	prompt_impure_async_callback '[async]' 3 '' 0 'worker crashed' 1

	assert_git_state_empty "when worker recovery fails" || return
	assert_equal 1 $render_called "prompt should be rendered after worker recovery clears git state" || return

	local async_job_called=0
	async_job() {
		async_job_called=1
	}
	prompt_impure_async_callback prompt_impure_async_vcs_info 0 "pwd ${(q)PWD} branch stale top /tmp/repo action rebase" 0 '' 0

	assert_empty "${prompt_impure_vcs_info[branch]-}" "stale callback should not restore branch after worker recovery fails" || return
	assert_empty "${prompt_impure_vcs_info[top]-}" "stale callback should not restore top-level after worker recovery fails" || return
	assert_equal 0 $async_job_called "stale callback should not queue async jobs after worker recovery fails" || return

	unfunction async_start_worker async_stop_worker prompt_impure_preprompt_render async_job
}

test_callback_recovery_calls_tasks_on_success() {
	# Simulate async_start_worker succeeding on recovery.
	async_start_worker() { return 0 }
	async_stop_worker() { : }
	async_register_callback() { : }
	async_worker_eval() { : }

	# Stub prompt_impure_vcs_tasks to detect if it gets called.
	local tasks_called=0
	prompt_impure_vcs_tasks() { tasks_called=1 }

	typeset -g prompt_impure_async_inited=0

	# Simulate the callback receiving an async worker crash (code 2).
	prompt_impure_async_callback '[async]' 2 '' 0 'worker crashed' 0

	assert_equal 1 $tasks_called "prompt_impure_vcs_tasks should be called when recovery succeeds" || return

	unfunction async_start_worker async_stop_worker async_register_callback async_worker_eval prompt_impure_vcs_tasks
}

test_dead_worker_no_stderr_leakage() {
	# Restore prompt_impure_async_git_tasks (earlier tests unfunction it).
	source ./impure.zsh >/dev/null 2>&1
	prompt_impure_preprompt_render() { : }

	# Simulate: worker was previously started but is now dead.
	# When recovery fails, the remaining async calls in prompt_impure_async_git_tasks
	# must not leak error messages to stderr. (GitHub issue #639)
	typeset -g prompt_impure_async_inited=1

	# Recovery will fail because the worker cannot be restarted.
	async_start_worker() { return 1 }
	async_stop_worker() {
		typeset -gA ASYNC_CALLBACKS
		unset "ASYNC_CALLBACKS[$1]"
	}
	async_register_callback() { : }
	async_flush_jobs() { : }

	# Register the callback (as prompt_impure_async_init would have done).
	typeset -gA ASYNC_CALLBACKS
	ASYNC_CALLBACKS[prompt_impure]="prompt_impure_async_callback"

	# Simulate dead worker behavior: the first call with a registered callback
	# invokes recovery (which fails and unregisters the callback). Subsequent
	# calls find no callback and print errors to stderr.
	async_worker_eval() {
		local worker=$1; shift
		typeset -gA ASYNC_CALLBACKS
		local callback=
		(( ${+ASYNC_CALLBACKS[$worker]} )) && callback=$ASYNC_CALLBACKS[$worker]
		if [[ -n $callback ]]; then
			$callback '[async]' 3 "" 0 "error: no such worker: $worker" 0
		else
			print -u2 "async_worker_eval: no such async worker: $worker"
		fi
		return 1
	}
	async_job() {
		local worker=$1; shift
		typeset -gA ASYNC_CALLBACKS
		local callback=
		(( ${+ASYNC_CALLBACKS[$worker]} )) && callback=$ASYNC_CALLBACKS[$worker]
		if [[ -n $callback ]]; then
			$callback '[async]' 3 "" 0 "error: no such worker: $worker" 0
		else
			print -u2 "async_job: no such async worker: $worker"
		fi
		return 1
	}

	local stderr_file=$TMPDIR/pure-test-stderr-$$
	prompt_impure_async_git_tasks 2>$stderr_file
	local stderr_output=$(<$stderr_file 2>/dev/null)

	assert_empty "$stderr_output" "prompt_impure_async_git_tasks must not leak error messages to stderr when worker is dead" || return

	unfunction async_start_worker async_stop_worker async_register_callback async_flush_jobs async_worker_eval async_job
}

main "$@"
