# Impure VCS status: Git (gitstatusd, or jobs in a zsh-async worker) and
# Jujutsu (jobs in the same worker). Sourced by impure.zsh.

# --- Jobs: run inside the async worker ------------------------------------

# Git aliases that pull or fetch, joined for use in a regex.
prompt_impure_async_git_aliases() {
	setopt localoptions noshwordsplit
	local line name
	local -a parts pullalias

	for line in ${(@f)"$(command git config --get-regexp '^alias\.')"}; do
		parts=(${=line})
		name=${parts[1]#alias.}
		shift parts
		[[ $parts =~ ^(.*\ )?(pull|fetch)(\ .*)?$ ]] && pullalias+=($name)
	done

	print -- ${(j:|:)pullalias}
}

prompt_impure_async_vcs_info() {
	setopt localoptions noshwordsplit

	# Configured here, inside the worker, so the user's vcs_info is untouched.
	zstyle ':vcs_info:*' enable git
	zstyle ':vcs_info:*' use-simple true
	zstyle ':vcs_info:*' max-exports 3
	# Branch (%b), top-level (%R), action (%a).
	zstyle ':vcs_info:git*' formats '%b' '%R' '%a'
	zstyle ':vcs_info:git*' actionformats '%b' '%R' '%a'

	vcs_info

	local -A info=(
		pwd    "$PWD"
		branch "${vcs_info_msg_0_//\%/%%}"
		top    "$vcs_info_msg_1_"
		action "$vcs_info_msg_2_"
	)
	print -r - ${(@kvq)info}
}

# Format staged counts as "+added ~modified -deleted" into REPLY.
prompt_impure_format_staging() {
	REPLY=
	(( $1 > 0 )) && REPLY+="+$1 "
	(( $2 > 0 )) && REPLY+="~$2 "
	(( $3 > 0 )) && REPLY+="-$3 "
	REPLY=${REPLY% }
}

# Format ahead/behind counts as "⇡1 ⇣3" into REPLY.
prompt_impure_format_arrows() {
	REPLY=
	(( ${1:-0} > 0 )) && REPLY+="${IMPURE_GIT_UP_ARROW:-⇡}$1 "
	(( ${2:-0} > 0 )) && REPLY+="${IMPURE_GIT_DOWN_ARROW:-⇣}$2 "
	REPLY=${REPLY% }
}

# Prints "STAGING|WORKING" (e.g. "+2 ~1|*") and returns 1 when dirty.
prompt_impure_async_git_dirty() {
	setopt localoptions noshwordsplit
	local untracked_dirty=$1 u_flag=-uno
	if [[ $untracked_dirty != 0 ]]; then
		[[ $(command git config --get status.showUntrackedFiles) == no ]] && u_flag=-uno || u_flag=-unormal
	fi

	# Keep `git status` from refreshing the index as a side effect.
	export GIT_OPTIONAL_LOCKS=0

	local output line
	output=$(command git status --porcelain $u_flag)
	[[ -z $output ]] && return 0

	local -i added=0 modified=0 deleted=0
	local working=
	for line in "${(f)output}"; do
		case ${line[1]} in
			A) (( added++ )) ;;
			M|R|C) (( modified++ )) ;;
			D) (( deleted++ )) ;;
		esac
		[[ ${line[2]} == [MTDUA] || $line == '??'* ]] && working='*'
	done

	local REPLY
	prompt_impure_format_staging $added $modified $deleted
	print -r -- "$REPLY|$working"
	return 1
}

prompt_impure_async_git_fetch() {
	setopt localoptions noshwordsplit
	local only_upstream=${1:-0}

	# Never prompt for credentials from the background.
	export GIT_TERMINAL_PROMPT=0
	export GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-"ssh"} -o BatchMode=yes"
	# An empty GPG_TTY makes pinentry-curses fail fast instead of stalling.
	export GPG_TTY=

	local -a remote
	if (( only_upstream )); then
		local ref
		ref=$(command git symbolic-ref -q HEAD)
		remote=($(command git for-each-ref --format='%(upstream:remotename) %(refname)' $ref))
		# No upstream for this branch.
		[[ -n $remote[1] ]] || return 97
	fi

	# 99: fetch failed, 98: fetch tried to prompt for a password.
	local fail_code=99

	# In MONITOR mode a fetch that prompts gets suspended, which we can detect
	# and kill; a prompting child would otherwise corrupt the worker.
	setopt localtraps monitor
	# Let HUP propagate when the worker is flushed.
	trap - HUP
	trap '
		trap - CHLD
		if [[ $jobstates = suspended* ]]; then
			fail_code=98
			kill %%
		fi
	' CHLD

	command git -c gc.auto=0 -c fetch.prune=false fetch \
		--quiet --no-tags --no-prune-tags --recurse-submodules=no \
		$remote &>/dev/null &
	wait $! || return $fail_code

	unsetopt monitor
	prompt_impure_async_git_arrows
}

prompt_impure_async_git_arrows() {
	command git rev-list --left-right --count HEAD...@'{u}'
}

# Prints the request generation, then "bookmarks|change_id|conflicts[ ~N]".
prompt_impure_async_jj_status() {
	print -r -- "${1:-0}"
	# jj/keep/ bookmarks are anonymous, and the heads/ prefix is noise.
	command jj log --no-graph -r '@' -T 'bookmarks.filter(|b| !b.name().starts_with("jj/keep/")).map(|b| b.name().replace("heads/", "")).join(" ") ++ "|" ++ change_id.shortest() ++ "|" ++ self.conflicted_files().len() ++ if(diff.files().len() > 0, " ~" ++ diff.files().len(), "")' 2>/dev/null
}

# Lower the worker's priority so disk-heavy `git status` stays polite.
prompt_impure_async_renice() {
	(( $+commands[renice] )) && command renice +15 -p $$
	(( $+commands[ionice] )) && command ionice -c 3 -p $$
	return 0
}

prompt_impure_async_worker_sync() {
	setopt localoptions noshwordsplit
	local sync_token=$1 target_pwd=$2 has_git_dir=$3 git_dir=$4 has_git_work_tree=$5 git_work_tree=$6

	if ! builtin cd -q "$target_pwd"; then
		builtin cd -q /
		unset GIT_DIR GIT_WORK_TREE
		print -r -- "prompt_impure_worker_sync:$sync_token:1"
		return 1
	fi

	(( has_git_dir )) && export GIT_DIR=$git_dir || unset GIT_DIR
	(( has_git_work_tree )) && export GIT_WORK_TREE=$git_work_tree || unset GIT_WORK_TREE
	print -r -- "prompt_impure_worker_sync:$sync_token:0"
}

# --- State -----------------------------------------------------------------

prompt_impure_clear_git_state() {
	unset prompt_impure_git_dirty prompt_impure_git_staging prompt_impure_git_arrows prompt_impure_git_fetch_pattern prompt_impure_git_last_fetch_timestamp prompt_impure_git_detached prompt_impure_git_conflicted
	typeset -gA prompt_impure_vcs_info=(branch '' top '' action '' pwd '')
}

prompt_impure_clear_jj_state() {
	typeset -g prompt_impure_jj_bookmark= prompt_impure_jj_changeid= prompt_impure_jj_working= prompt_impure_jj_conflicted=
}

prompt_impure_in_jj_repo() {
	local dir=$PWD
	until [[ -d $dir/.jj ]]; do
		[[ $dir == / ]] && return 1
		dir=${dir:h}
	done
}

# --- gitstatusd (optional fast path) ---------------------------------------

# Sets prompt_impure_gitstatus_inited to 1 or 0; callers try this only once.
prompt_impure_gitstatus_init() {
	typeset -gi prompt_impure_gitstatus_inited=0

	local plugin=${GITSTATUS_PLUGIN_ZSH:-}
	if [[ -z $plugin ]]; then
		for plugin in "${GITSTATUS_DIR:-}/gitstatus.plugin.zsh" \
			"${XDG_DATA_HOME:-$HOME/.local/share}/gitstatus/gitstatus.plugin.zsh" \
			/usr/share/gitstatus/gitstatus.plugin.zsh; do
			[[ -r $plugin ]] && break
			plugin=
		done
	fi
	[[ -r $plugin ]] || return 1

	# `builtin source` dodges user source() wrappers that leak $1 into the
	# plugin and break its dynamic typeset.
	() {
		emulate -L zsh
		setopt no_xtrace
		builtin source "$plugin" 2>/dev/null
	} || return 1
	gitstatus_start -s -1 -u -1 -t 5 IMPURE 2>/dev/null || return 1
	prompt_impure_gitstatus_inited=1
}

# Fill the Git state from gitstatusd; returns 1 outside a repo.
prompt_impure_gitstatus_query() {
	gitstatus_query -d "$PWD" IMPURE || return 1
	[[ $VCS_STATUS_RESULT == ok-(sync|async) ]] || return 1

	typeset -gA prompt_impure_vcs_info=(
		branch "$VCS_STATUS_LOCAL_BRANCH"
		top    "$VCS_STATUS_WORKDIR"
		action "$VCS_STATUS_ACTION"
		pwd    "$PWD"
	)

	typeset -g prompt_impure_git_dirty=
	(( VCS_STATUS_HAS_UNSTAGED || VCS_STATUS_HAS_UNTRACKED )) && prompt_impure_git_dirty='*'

	# Conflicts are shown on their own, so they don't count as modified.
	local REPLY
	prompt_impure_format_staging $VCS_STATUS_NUM_STAGED_NEW \
		$(( VCS_STATUS_NUM_STAGED - VCS_STATUS_NUM_STAGED_NEW - VCS_STATUS_NUM_STAGED_DELETED - VCS_STATUS_NUM_CONFLICTED )) \
		$VCS_STATUS_NUM_STAGED_DELETED
	typeset -g prompt_impure_git_staging=$REPLY

	prompt_impure_format_arrows $VCS_STATUS_COMMITS_AHEAD $VCS_STATUS_COMMITS_BEHIND
	typeset -g prompt_impure_git_arrows=$REPLY

	typeset -g prompt_impure_git_detached=
	[[ -z $VCS_STATUS_LOCAL_BRANCH ]] && prompt_impure_git_detached=${VCS_STATUS_COMMIT[1,8]}

	typeset -g prompt_impure_git_conflicted=
	(( VCS_STATUS_NUM_CONFLICTED )) && prompt_impure_git_conflicted="!$VCS_STATUS_NUM_CONFLICTED"
	return 0
}

# --- Worker lifecycle ------------------------------------------------------

prompt_impure_async_init() {
	(( ${prompt_impure_async_inited:-0} )) && return
	typeset -g prompt_impure_async_inited=1
	# A fresh worker is not in $PWD yet.
	typeset -gA prompt_impure_worker_env=()
	async
	if ! async_start_worker "prompt_impure" -u -n 2>/dev/null; then
		# e.g. zpty permission denied: run without async status.
		prompt_impure_async_inited=0
		return 1
	fi
	async_register_callback "prompt_impure" prompt_impure_async_callback
	async_worker_eval "prompt_impure" prompt_impure_async_renice
}

# Start the worker and move it into $PWD; requests run in order, so the reply
# is never awaited (a flush could swallow it) and only a failure is acted on.
prompt_impure_async_ready() {
	setopt localoptions noshwordsplit

	prompt_impure_async_init || return

	typeset -gA prompt_impure_worker_env
	local cur_git_dir=${GIT_DIR-__unset__}
	local cur_git_work_tree=${GIT_WORK_TREE-__unset__}
	if [[ $PWD == ${prompt_impure_worker_env[pwd]-} &&
		$cur_git_dir == ${prompt_impure_worker_env[git_dir]-} &&
		$cur_git_work_tree == ${prompt_impure_worker_env[git_work_tree]-} ]]; then
		return 0
	fi

	# Jobs still running belong to the old directory.
	async_flush_jobs "prompt_impure"

	typeset -gi prompt_impure_worker_sync_token
	(( prompt_impure_worker_sync_token++ ))
	if ! async_worker_eval "prompt_impure" \
		prompt_impure_async_worker_sync $prompt_impure_worker_sync_token "$PWD" ${+GIT_DIR} "${GIT_DIR-}" ${+GIT_WORK_TREE} "${GIT_WORK_TREE-}"; then
		typeset -gA prompt_impure_worker_env=()
		return 1
	fi
	typeset -gA prompt_impure_worker_env=(pwd "$PWD" git_dir "$cur_git_dir" git_work_tree "$cur_git_work_tree")
}

# Stop the worker on exit so its zpty can't hold the terminal open.
prompt_impure_zshexit() {
	async_stop_worker prompt_impure 2>/dev/null
}

# --- Dispatch (from precmd) ------------------------------------------------

# jj takes precedence over git. The path is walked only on cd; a cached "no"
# is rechecked with one stat in case `jj git init` just ran here.
prompt_impure_vcs_tasks() {
	if [[ $PWD != ${prompt_impure_jj_repo_check_pwd-} ]] ||
		{ (( ! ${prompt_impure_jj_repo_check:-0} )) && [[ -d $PWD/.jj ]] }; then
		typeset -g prompt_impure_jj_repo_check_pwd=$PWD
		prompt_impure_in_jj_repo
		typeset -gi prompt_impure_jj_repo_check=$(( ! $? ))
	fi

	if (( prompt_impure_jj_repo_check )) && zstyle -T ":prompt:impure:jj" show; then
		prompt_impure_clear_git_state
		prompt_impure_async_jj_tasks
	else
		prompt_impure_clear_jj_state
		prompt_impure_async_git_tasks
	fi
}

prompt_impure_async_jj_tasks() {
	prompt_impure_async_ready || return

	if [[ $PWD != ${prompt_impure_jj_pwd-} ]]; then
		typeset -g prompt_impure_jj_pwd=$PWD
		prompt_impure_clear_jj_state
	fi

	# jj status changes without a cd (e.g. jj new), so always ask. The unique
	# worker drops this while a jj job runs; the callback retries stale ones.
	typeset -gi prompt_impure_jj_generation
	(( prompt_impure_jj_generation++ ))
	async_job "prompt_impure" prompt_impure_async_jj_status $prompt_impure_jj_generation
}

prompt_impure_async_git_tasks() {
	setopt localoptions noshwordsplit

	# The callback drops in-flight Git results; flushing here would kill jobs
	# for no gain.
	if ! zstyle -T ":prompt:impure:git" show; then
		prompt_impure_clear_git_state
		return
	fi

	(( ${+prompt_impure_gitstatus_inited} )) || prompt_impure_gitstatus_init
	if (( prompt_impure_gitstatus_inited )); then
		# gitstatusd answers synchronously but never fetches.
		if prompt_impure_gitstatus_query; then
			prompt_impure_async_ready && prompt_impure_async_fetch
		else
			prompt_impure_clear_git_state
		fi
		return
	fi

	if ! prompt_impure_async_ready; then
		prompt_impure_clear_git_state
		return
	fi

	# Left the working tree, rather than descended into it.
	[[ $PWD == ${prompt_impure_vcs_info[pwd]-}* ]] || prompt_impure_clear_git_state

	async_job "prompt_impure" prompt_impure_async_vcs_info || return
	[[ -n $prompt_impure_vcs_info[top] ]] || return
	prompt_impure_async_refresh
}

# Queue a background fetch, throttled per repository. When skipped, queue
# the optional fallback job ($1) instead.
prompt_impure_async_fetch() {
	local top=$prompt_impure_vcs_info[top]
	local -F now=$EPOCHREALTIME
	if (( ! ${IMPURE_GIT_PULL:-1} )) || [[ $top == $HOME ]] ||
		{ [[ $top == ${prompt_impure_git_last_fetch_top-} ]] &&
			(( now - ${prompt_impure_git_last_fetch_timestamp:-0} < ${IMPURE_GIT_FETCH_INTERVAL:-60} )) }; then
		[[ -z $1 ]] || async_job "prompt_impure" $1
		return
	fi

	typeset -gF prompt_impure_git_last_fetch_timestamp=$now
	typeset -g prompt_impure_git_last_fetch_top=$top
	zstyle -t :prompt:impure:git:fetch only_upstream
	async_job "prompt_impure" prompt_impure_async_git_fetch $(( ? == 0 ))
}

prompt_impure_async_refresh() {
	# Look up pull/fetch aliases once per working tree.
	if [[ -z $prompt_impure_git_fetch_pattern ]]; then
		typeset -g prompt_impure_git_fetch_pattern="pull|fetch"
		async_job "prompt_impure" prompt_impure_async_git_aliases || return
	fi
	prompt_impure_async_fetch prompt_impure_async_git_arrows || return
	async_job "prompt_impure" prompt_impure_async_git_dirty ${IMPURE_GIT_UNTRACKED_DIRTY:-1}
}

# --- Results ---------------------------------------------------------------

prompt_impure_async_callback() {
	setopt localoptions noshwordsplit
	local job=$1 code=$2 output=$3 exec_time=$4 next_pending=$6
	local do_render=0

	[[ $job == '[async]' ]] || (( ${prompt_impure_async_inited:-0} )) || return

	# Drop results from another directory (or a disabled integration) without
	# returning, which would strand a render another job in this batch asked for.
	case $job in
		prompt_impure_async_(vcs_info|git_*))
			[[ ${prompt_impure_worker_env[pwd]-} == $PWD ]] || job='[stale]'
			zstyle -T ":prompt:impure:git" show || job='[stale]'
			;;
		prompt_impure_async_jj_status)
			local jj_generation=${output%%$'\n'*}
			output=${${output#$jj_generation}#$'\n'}
			if [[ ${prompt_impure_worker_env[pwd]-} != $PWD ]]; then
				job='[stale]'
			elif [[ $jj_generation != ${prompt_impure_jj_generation-} ]]; then
				# A newer request was dropped while this ran; ask again.
				async_job "prompt_impure" prompt_impure_async_jj_status $prompt_impure_jj_generation
				job='[stale]'
			fi
			;;
	esac

	case $job in
		\[async])
			# Exit codes 2, 3 and 130 mean the worker died; restart it.
			if (( code == 2 || code == 3 || code == 130 )); then
				typeset -g prompt_impure_async_inited=0
				async_stop_worker prompt_impure
				if prompt_impure_async_init; then
					prompt_impure_vcs_tasks
				else
					prompt_impure_clear_git_state
					do_render=1
					next_pending=0
				fi
				unset prompt_impure_async_render_requested
			fi
			;;
		\[async/eval])
			# The latest sync failed to enter $PWD, or an eval died before
			# reporting: forget the sync so the next prompt retries.
			local worker_sync=${(M)${(f)output}:#prompt_impure_worker_sync:*}
			if [[ $worker_sync == prompt_impure_worker_sync:${prompt_impure_worker_sync_token-}:1 ]] ||
				{ [[ -z $worker_sync ]] && (( code )) }; then
				typeset -gA prompt_impure_worker_env=()
				prompt_impure_clear_git_state
				prompt_impure_clear_jj_state
				do_render=1
				next_pending=0
			fi
			;;
		prompt_impure_async_vcs_info)
			local -A info=("${(Q@)${(z)output}}")
			if [[ $info[pwd] == $PWD ]]; then
				# Remember the shallowest directory seen in this working tree,
				# so leaving it can be told apart from descending into it.
				if [[ $info[top] != $prompt_impure_vcs_info[top] || $prompt_impure_vcs_info[pwd] == $PWD* ]]; then
					prompt_impure_vcs_info[pwd]=$PWD
				fi
				# Just entered a working tree.
				[[ -n $info[top] && -z $prompt_impure_vcs_info[top] ]] && prompt_impure_async_refresh

				prompt_impure_vcs_info[branch]=$info[branch]
				prompt_impure_vcs_info[top]=$info[top]
				prompt_impure_vcs_info[action]=$info[action]
				do_render=1
			fi
			;;
		prompt_impure_async_git_aliases)
			[[ -n $output ]] && prompt_impure_git_fetch_pattern+="|$output"
			;;
		prompt_impure_async_git_dirty)
			local staging= dirty=
			(( code )) && staging=${output%%|*} dirty=${output#*|}
			if [[ $staging != ${prompt_impure_git_staging-} || $dirty != ${prompt_impure_git_dirty-} ]]; then
				typeset -g prompt_impure_git_staging=$staging prompt_impure_git_dirty=$dirty
				do_render=1
			fi
			;;
		prompt_impure_async_git_fetch|prompt_impure_async_git_arrows)
			local REPLY=
			case $code in
				0) prompt_impure_format_arrows ${(ps:\t:)output} ;;
				# Fetch failed or wanted a password: keep what we had.
				98|99) REPLY=${prompt_impure_git_arrows-} ;;
				# 97 or rev-list failing: no upstream.
			esac
			if [[ $REPLY != ${prompt_impure_git_arrows-} ]]; then
				typeset -g prompt_impure_git_arrows=$REPLY
				do_render=1
			fi
			;;
		prompt_impure_async_jj_status)
			# bookmark, change id, working copy changes, conflicts
			local -a fields counts jj=('' '' '' '')
			if (( code == 0 )); then
				fields=("${(@s:|:)output}")
				counts=(${=fields[3]})
				jj=("$fields[1]" "$fields[2]" "${counts[2]-}" '')
				(( counts[1] )) && jj[4]="!$counts[1]"
			fi
			if [[ ${(j:|:)jj} != "$prompt_impure_jj_bookmark|$prompt_impure_jj_changeid|$prompt_impure_jj_working|$prompt_impure_jj_conflicted" ]]; then
				typeset -g prompt_impure_jj_bookmark=$jj[1] prompt_impure_jj_changeid=$jj[2] \
					prompt_impure_jj_working=$jj[3] prompt_impure_jj_conflicted=$jj[4]
				do_render=1
			fi
			;;
	esac

	if (( next_pending )); then
		(( do_render )) && typeset -g prompt_impure_async_render_requested=1
		return
	fi

	[[ ${prompt_impure_async_render_requested:-$do_render} == 1 ]] && prompt_impure_preprompt_render
	unset prompt_impure_async_render_requested
}
