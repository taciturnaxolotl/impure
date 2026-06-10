# Impure
# Forked from Pure by Sindre Sorhus
# https://github.com/sindresorhus/pure
# MIT License

# For my own and others sanity
# git:
# %b => current branch
# %a => current action (rebase/merge)
# prompt:
# %F => color dict
# %f => reset color
# %~ => current path
# %* => time
# %n => username
# %m => shortname host
# %(?..) => prompt conditional - %(condition.true.false)
# terminal codes:
# \e7   => save cursor position
# \e[2A => move cursor 2 lines up
# \e[1G => go to position 1 in terminal
# \e8   => restore cursor position
# \e[K  => clears everything after the cursor on the current line
# \e[2K => clear everything on the current line


# Turns seconds into human readable time.
# 165392 => 1d 21h 56m 32s
# https://github.com/sindresorhus/pretty-time-zsh
prompt_impure_human_time_to_var() {
	local -F total_seconds=$1
	local var=$2
	local -i days=$(( total_seconds / 60 / 60 / 24 ))
	local -i hours=$(( total_seconds / 60 / 60 % 24 ))
	local -i minutes=$(( total_seconds / 60 % 60 ))
	local -F seconds=$(( total_seconds - days*86400 - hours*3600 - minutes*60 ))

	local formatted=
	(( days > 0 )) && formatted+="${days}d "
	(( hours > 0 )) && formatted+="${hours}h "
	(( minutes > 0 )) && formatted+="${minutes}m "
	if (( minutes > 0 || hours > 0 || days > 0 )); then
		local -i isec=$(( seconds ))
		formatted+="${isec}s"
	else
		local -F sec=$seconds
		formatted+="$(printf '%.2f' $sec)s"
	fi

	typeset -g "${var}"="${formatted}"
}

# Stores (into prompt_impure_cmd_exec_time) the execution
# time of the last command if set threshold was exceeded.
prompt_impure_check_cmd_exec_time() {
	local -F elapsed=$(( EPOCHREALTIME - ${prompt_impure_cmd_timestamp:-$EPOCHREALTIME} ))
	typeset -g prompt_impure_cmd_exec_time=
	(( elapsed >= ${IMPURE_CMD_MAX_EXEC_TIME:-3} )) && {
		prompt_impure_human_time_to_var $elapsed "prompt_impure_cmd_exec_time"
	}
}

prompt_impure_set_title() {
	setopt localoptions noshwordsplit

	# Allow disabling title management.
	zstyle -T ":prompt:impure:title" show || return

	# Emacs terminal does not support settings the title.
	(( ${+EMACS} || ${+INSIDE_EMACS} )) && return

	case $TTY in
		# Don't set title over serial console.
		/dev/ttyS[0-9]*) return;;
	esac

	# Show hostname if connected via SSH and host display is enabled.
	local hostname=
	if (( psvar[13] )) && (( ${prompt_impure_state[show_host]:-1} )); then
		# Expand in-place in case ignore-escape is used.
		hostname="${(%):-(%m) }"
	fi

	local -a opts
	case $1 in
		expand-prompt) opts=(-P);;
		ignore-escape) opts=(-r);;
	esac

	# Set title atomically in one print statement so that it works when XTRACE is enabled.
	print -n $opts $'\e]0;'${hostname}${2}$'\a'
}

prompt_impure_preexec() {
	if [[ -n $prompt_impure_git_fetch_pattern ]]; then
		# Detect when Git is performing pull/fetch, including Git aliases.
		local -H MATCH MBEGIN MEND match mbegin mend
		if [[ $2 =~ (git|hub)\ (.*\ )?($prompt_impure_git_fetch_pattern)(\ .*)?$ ]]; then
			# We must flush the async jobs to cancel our git fetch in order
			# to avoid conflicts with the user issued pull / fetch.
			async_flush_jobs 'prompt_impure'
		fi
	fi

	typeset -gF prompt_impure_cmd_timestamp=$EPOCHREALTIME

	# Shows the current directory and executed command in the title while a process is active.
	prompt_impure_set_title 'ignore-escape' "$PWD:t: $2"

	# Disallow Python virtualenv from updating the prompt. Set it to 20 if
	# untouched by the user to indicate that Impure modified it. Here we use
	# the magic number 20, same as in `psvar`.
	export VIRTUAL_ENV_DISABLE_PROMPT=${VIRTUAL_ENV_DISABLE_PROMPT:-20}
}

# Change the colors if their value are different from the current ones.
prompt_impure_set_colors() {
	local color_temp key value
	for key value in ${(kv)prompt_impure_colors}; do
		zstyle -t ":prompt:impure:$key" color "$value" && continue
		case $? in
			1) # The current style is different from the one from zstyle.
				zstyle -s ":prompt:impure:$key" color color_temp
				prompt_impure_colors[${key}]=$color_temp ;;
			2) # No style is defined.
				prompt_impure_colors[${key}]=${prompt_impure_colors_default[${key}]} ;;
		esac
	done

	prompt_impure_set_path_separator

	return 0
}

prompt_impure_set_path_separator() {
	local path_color=$prompt_impure_colors[path]

	typeset -g prompt_impure_path_segment="%F{${path_color}}%~%f"

	if zstyle -t ':prompt:impure:path:separator' dim; then
		typeset -g prompt_impure_path_separator_dimmed=1
	else
		typeset -g prompt_impure_path_separator_dimmed=
	fi
}

prompt_impure_render_dimmed_path() {
	setopt localoptions noshwordsplit

	# This runs from PROMPT_SUBST so directory changes followed by reset-prompt redraw correctly without precmd.
	local current_path=${1:-${(%):-%~}}
	current_path=${current_path//\%/%%}

	local separator=$'%{\e[2m%}/%{\e[22m%}'
	# Keep the leading / on absolute paths at full brightness.
	local prefix=
	if [[ $current_path == /* ]]; then
		prefix=/
		current_path=${current_path:1}
	fi

	local path_color=$prompt_impure_colors[path]

	print -n -r -- "%F{${path_color}}${prefix}${current_path//\//$separator}%f"
}

prompt_impure_preprompt_render() {
	setopt localoptions noshwordsplit

	unset prompt_impure_async_render_requested

	typeset -g prompt_impure_git_branch_color=$prompt_impure_colors[git:branch]

	# Update psvar values. PROMPT uses %(NV.true.false) to conditionally
	# render each part. See prompt_impure_setup for the PROMPT template.
	#
	# psvar[12]: Suspended jobs symbol.
	psvar[12]=
	((${(M)#jobstates:#suspended:*} != 0)) && psvar[12]=${IMPURE_SUSPENDED_JOBS_SYMBOL-✦}

	# psvar[13]: Username flag (set once in prompt_impure_state_setup).

	# psvar[14]: Git branch name.
	psvar[14]=${prompt_impure_vcs_info[branch]}

	# psvar[15]: Git staging summary (e.g. "+2 ~1").
	psvar[15]=${prompt_impure_git_staging}

	# psvar[16]: Git working tree dirty marker ("*").
	psvar[16]=${prompt_impure_git_dirty}

	# psvar[17]: Git action (rebase/merge).
	psvar[17]=${prompt_impure_vcs_info[action]}

	# psvar[18]: Git arrows with counts (e.g. ⇡1 ⇣3).
	psvar[18]=
	[[ -n $prompt_impure_git_arrows ]] && psvar[18]=$prompt_impure_git_arrows


	# psvar[20]: Command execution time (used in RPROMPT).
	psvar[20]=${prompt_impure_cmd_exec_time}

	# psvar[21]: virtualenv/nix-shell name — set in precmd, not here.

	# psvar[22]: Custom prefix, psvar[23]: Custom suffix.
	# Set by the user-defined prompt_impure_precustom function.
	psvar[22]=
	psvar[23]=
	if (( $+functions[prompt_impure_precustom] )); then
		prompt_impure_precustom
	fi

	# psvar[24]: ZMX session tag.
	psvar[24]=
	[[ -n ${ZMX_SESSION:-} ]] && psvar[24]="[${ZMX_SESSION}]"

	# psvar[25]: Jujutsu bookmark(s).
	# psvar[26]: Jujutsu change ID (rendered in cyan).
	# psvar[27]: Jujutsu working set changes.
	psvar[25]=${prompt_impure_jj_bookmark}
	psvar[26]=${prompt_impure_jj_changeid}
	psvar[27]=${prompt_impure_jj_working}

	# Build a fingerprint from all dynamic prompt components to detect changes
	# without expanding PROMPT (which forks a subshell when dimmed path is on).
	local -a prompt_fingerprint_parts=(
		"${psvar[12]}"
		"${psvar[13]}"
		"${psvar[14]}"
		"${psvar[15]}"
		"${psvar[16]}"
		"${psvar[17]}"
		"${psvar[18]}"
		"${psvar[19]}"
		# psvar[20] (exec time) excluded: changes every command, handled by precmd.
		"${psvar[21]}"
		"${psvar[22]}"
		"${psvar[23]}"
		"${psvar[24]}"
		"${psvar[25]}"
		"${psvar[26]}"
		"${psvar[27]}"
		"${prompt_impure_state[prompt]}"
		"${prompt_impure_git_branch_color}"
		"${PWD}"
	)
	local prompt_fingerprint="${(pj:|:)${(@qqq)prompt_fingerprint_parts}}"

	if [[ $1 != precmd ]] && [[ $prompt_impure_last_prompt != $prompt_fingerprint ]]; then
		# Redraw the prompt.
		prompt_impure_reset_prompt
	fi

	typeset -g prompt_impure_last_prompt=$prompt_fingerprint
}

# Instant prompt cleanup: restore fds, replay captured output, redraw prompt.
# Validates fds before use to prevent errors if they were closed externally.
prompt_impure_instant_prompt_cleanup() {
	(( ${IMPURE_INSTANT_PROMPT_ACTIVE:-0} )) || return 0
	typeset -g IMPURE_INSTANT_PROMPT_ACTIVE=0
	if (( ${IMPURE_IP_FD_1:-0} )) && { true >&${IMPURE_IP_FD_1} } 2>/dev/null; then
		exec 0<&${IMPURE_IP_FD_0} 1>&${IMPURE_IP_FD_1} 2>&${IMPURE_IP_FD_2} \
			{IMPURE_IP_FD_0}>&- {IMPURE_IP_FD_1}>&- {IMPURE_IP_FD_2}>&-
	fi
	# Clear the instant prompt from screen: restore cursor, erase below.
	zmodload zsh/terminfo 2>/dev/null
	print -rn -- "${terminfo[rc]:-$'\e8'}${terminfo[ed]:-$'\e[J'}"
	# Replay any captured init output above the prompt.
	if [[ -s "${IMPURE_IP_OUTPUT_FILE:-}" ]]; then
		cat "$IMPURE_IP_OUTPUT_FILE" 2>/dev/null
	fi
	rm -f "${IMPURE_IP_OUTPUT_FILE:-}" 2>/dev/null
	unset IMPURE_IP_FD_0 IMPURE_IP_FD_1 IMPURE_IP_FD_2 IMPURE_IP_OUTPUT_FILE
	prompt_impure_reset_prompt
}

prompt_impure_precmd() {
	setopt localoptions noshwordsplit

	# Clean up instant prompt if active.
	prompt_impure_instant_prompt_cleanup

	# Check execution time and store it in a variable.
	prompt_impure_check_cmd_exec_time
	unset prompt_impure_cmd_timestamp

	# Shows the full path in the title.
	prompt_impure_set_title 'expand-prompt' '%~'

	# Modify the colors if some have changed..
	prompt_impure_set_colors

	# Restore full prompt if transient swapped it.
	if [[ -n ${prompt_impure_saved_prompt:-} ]]; then
		PROMPT=$prompt_impure_saved_prompt
		RPROMPT=$prompt_impure_saved_rprompt
		unset prompt_impure_saved_prompt prompt_impure_saved_rprompt
		prompt_impure_build_rprompt
	fi

	# Handle Ctrl+C: install TRAPINT so transient fires on interrupt too.
	TRAPINT() {
		typeset -g prompt_impure_transient=1
		return $(( 128 + $1 ))
	}

	# Perform async Git dirty check and fetch.
	prompt_impure_async_tasks

	# Perform async Jujutsu status check.
	prompt_impure_async_jj_tasks

	# Check if we should display the virtual env (psvar[21]).
	psvar[21]=
	if zstyle -T ":prompt:impure:environment:virtualenv" show; then
		# When VIRTUAL_ENV_DISABLE_PROMPT is empty, it was unset by the user and
		# Impure should take back control.
		if [[ -n $VIRTUAL_ENV ]] && [[ -z $VIRTUAL_ENV_DISABLE_PROMPT || $VIRTUAL_ENV_DISABLE_PROMPT = 20 ]]; then
			if [[ -n $VIRTUAL_ENV_PROMPT ]]; then
				psvar[21]="${VIRTUAL_ENV_PROMPT}"
			else
				psvar[21]="${VIRTUAL_ENV:t}"
			fi
			export VIRTUAL_ENV_DISABLE_PROMPT=20
		fi
	fi

	# Nix package manager integration. If used from within 'nix shell' - shell name is shown like so:
	# ~/Projects/flake-utils-plus master
	# flake-utils-plus ❯
	if zstyle -T ":prompt:impure:environment:nix-shell" show; then
		if [[ -n $IN_NIX_SHELL ]]; then
			psvar[21]="impure"
		fi
	fi

	# Make sure VIM prompt is reset.
	prompt_impure_reset_prompt_symbol

	# Print the preprompt.
	prompt_impure_preprompt_render "precmd"

	if [[ -n $ZSH_THEME ]]; then
		print "WARNING: Oh My Zsh themes are enabled (ZSH_THEME='${ZSH_THEME}'). Impure might not be working correctly."
		print "For more information, see: https://github.com/sindresorhus/pure#oh-my-zsh"
		unset ZSH_THEME  # Only show this warning once.
	fi
}

prompt_impure_async_git_aliases() {
	setopt localoptions noshwordsplit
	local -a gitalias pullalias

	# List all aliases and split on newline.
	gitalias=(${(@f)"$(command git config --get-regexp "^alias\.")"})
	for line in $gitalias; do
		parts=(${(@)=line})           # Split line on spaces.
		aliasname=${parts[1]#alias.}  # Grab the name (alias.[name]).
		shift parts                   # Remove `aliasname`

		# Check alias for pull or fetch. Must be exact match.
		if [[ $parts =~ ^(.*\ )?(pull|fetch)(\ .*)?$ ]]; then
			pullalias+=($aliasname)
		fi
	done

	print -- ${(j:|:)pullalias}  # Join on pipe, for use in regex.
}

prompt_impure_async_vcs_info() {
	setopt localoptions noshwordsplit

	# Configure `vcs_info` inside an async task. This frees up `vcs_info`
	# to be used or configured as the user pleases.
	zstyle ':vcs_info:*' enable git
	zstyle ':vcs_info:*' use-simple true
	# Only export four message variables from `vcs_info`.
	zstyle ':vcs_info:*' max-exports 3
	# Export branch (%b), Git toplevel (%R), action (rebase/cherry-pick) (%a)
	zstyle ':vcs_info:git*' formats '%b' '%R' '%a'
	zstyle ':vcs_info:git*' actionformats '%b' '%R' '%a'

	vcs_info

	local -A info
	info[pwd]=$PWD
	info[branch]=${vcs_info_msg_0_//\%/%%}
	info[top]=$vcs_info_msg_1_
	info[action]=$vcs_info_msg_2_

	print -r - ${(@kvq)info}
}

# Check if a Git repo is dirty. Outputs oh-my-posh style summary:
# STAGING|WORKING where STAGING is like "+2 ~1" and WORKING is "*" or empty.
prompt_impure_async_git_dirty() {
	setopt localoptions noshwordsplit
	local untracked_dirty=$1
	local untracked_git_mode=$(command git config --get status.showUntrackedFiles)
	if [[ "$untracked_git_mode" != 'no' ]]; then
		untracked_git_mode='normal'
	fi

	# Prevent e.g. `git status` from refreshing the index as a side effect.
	export GIT_OPTIONAL_LOCKS=0

	local u_flag
	if [[ $untracked_dirty = 0 ]]; then
		u_flag='-uno'
	else
		u_flag="-u${untracked_git_mode}"
	fi

	local output
	output=$(command git status --porcelain $u_flag)
	[[ -z $output ]] && return 0

	local staged_add=0 staged_mod=0 staged_del=0
	local working_dirty=0 line
	for line in "${(f)output}"; do
		# Staging area (first column).
		case ${line[1]} in
			A) (( staged_add++ )) ;;
			M|R|C) (( staged_mod++ )) ;;
			D) (( staged_del++ )) ;;
		esac
		# Working tree (second column).
		[[ ${line[2]} == [MTDUA] ]] && working_dirty=1
		# Untracked.
		[[ $line == '??'* ]] && working_dirty=1
	done

	# Build staging summary: +N ~N -N (only non-zero parts).
	local staging=""
	(( staged_add )) && staging+="+${staged_add} "
	(( staged_mod )) && staging+="~${staged_mod} "
	(( staged_del )) && staging+="-${staged_del} "
	staging=${staging% }  # trim trailing space

	# Output: staging|working (* or empty)
	local working=""
	(( working_dirty )) && working="*"
	print -r -- "${staging}|${working}"
	return 1
}

prompt_impure_async_git_fetch() {
	setopt localoptions noshwordsplit

	local only_upstream=${1:-0}

	# Sets `GIT_TERMINAL_PROMPT=0` to disable authentication prompt for Git fetch (Git 2.3+).
	export GIT_TERMINAL_PROMPT=0
	# Set SSH `BachMode` to disable all interactive SSH password prompting.
	export GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-"ssh"} -o BatchMode=yes"

	# If gpg-agent is set to handle SSH keys for `git fetch`, make
	# sure it doesn't corrupt the parent TTY.
	# Setting an empty GPG_TTY forces pinentry-curses to close immediately rather
	# than stall indefinitely waiting for user input.
	export GPG_TTY=

	local -a remote
	if ((only_upstream)); then
		local ref
		ref=$(command git symbolic-ref -q HEAD)
		# Set remote to only fetch information for the current branch.
		remote=($(command git for-each-ref --format='%(upstream:remotename) %(refname)' $ref))
		if [[ -z $remote[1] ]]; then
			# No remote specified for this branch, skip fetch.
			return 97
		fi
	fi

	# Default return code, which indicates Git fetch failure.
	local fail_code=99

	# Guard against all forms of password prompts. By setting the shell into
	# MONITOR mode we can notice when a child process prompts for user input
	# because it will be suspended. Since we are inside an async worker, we
	# have no way of transmitting the password and the only option is to
	# kill it. If we don't do it this way, the process will corrupt with the
	# async worker.
	setopt localtraps monitor

	# Make sure local HUP trap is unset to allow for signal propagation when
	# the async worker is flushed.
	trap - HUP

	trap '
		# Unset trap to prevent infinite loop
		trap - CHLD
		if [[ $jobstates = suspended* ]]; then
			# Set fail code to password prompt and kill the fetch.
			fail_code=98
			kill %%
		fi
	' CHLD

	# Do git fetch and avoid fetching tags or
	# submodules to speed up the process.
	command git -c gc.auto=0 -c fetch.prune=false fetch \
		--quiet \
		--no-tags \
		--no-prune-tags \
		--recurse-submodules=no \
		$remote &>/dev/null &
	wait $! || return $fail_code

	unsetopt monitor

	# Check arrow status after a successful `git fetch`.
	prompt_impure_async_git_arrows
}

prompt_impure_async_git_arrows() {
	setopt localoptions noshwordsplit
	command git rev-list --left-right --count HEAD...@'{u}'
}


# Walk up from $PWD looking for a .jj directory. Returns 0 if inside a
# Jujutsu repo, 1 otherwise. Shared by the sync dispatch path and the
# async worker so the detection logic lives in exactly one place.
prompt_impure_in_jj_repo() {
	local dir=$PWD
	while [[ $dir != "/" ]]; do
		[[ -d "$dir/.jj" ]] && return 0
		dir=${dir:h}
	done
	[[ -d "/.jj" ]]
}

# Async jujutsu status: get change ID and working set modifications.
# Mirrors the git async pattern — runs in the background worker, never blocks.
prompt_impure_async_jj_status() {
	setopt localoptions noshwordsplit

	# Skip unless inside a jj repo.
	prompt_impure_in_jj_repo || return 1

	# Get bookmark and change ID in one call.
	local jj_info
	# Use | as delimiter between bookmarks and change ID for reliable parsing.
	# Filter out jj/keep/ (auto-generated anonymous branch bookmarks) and strip heads/ prefix.
	jj_info=$(command jj log --no-graph -r '@' -T 'bookmarks.filter(|b| !b.name().starts_with("jj/keep/")).map(|b| b.name().replace("heads/", "")).join(" ") ++ "|" ++ change_id.shortest()' 2>/dev/null) || return 1

	# Get working copy status: count changed files via process substitution
	# to avoid storing the full output in a variable.
	local count=0
	local in_changes=0
	local line
	while IFS= read -r line; do
		if [[ $line == "Working copy changes:" ]]; then
			in_changes=1
			continue
		fi
		(( in_changes )) || continue
		[[ -z $line || $line == "Working copy"* || $line == "Parent commit"* ]] && break
		(( count++ ))
	done < <(command jj status --color=never 2>/dev/null)

	local working_changes=""
	(( count > 0 )) && working_changes=" ~${count}"

	# Output: bookmark(s) space change_id space working_changes
	# The renderer will split and color the change_id cyan.
	print -r -- "${jj_info}${working_changes}"
}

# Try to lower the priority of the worker so that disk heavy operations
# like `git status` has less impact on the system responsivity.
prompt_impure_async_renice() {
	setopt localoptions noshwordsplit

	if command -v renice >/dev/null; then
		command renice +15 -p $$
	fi

	if command -v ionice >/dev/null; then
		command ionice -c 3 -p $$
	fi
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

	if (( has_git_dir )); then
		export GIT_DIR=$git_dir
	else
		unset GIT_DIR
	fi

	if (( has_git_work_tree )); then
		export GIT_WORK_TREE=$git_work_tree
	else
		unset GIT_WORK_TREE
	fi

	print -r -- "prompt_impure_worker_sync:$sync_token:0"
}

prompt_impure_clear_git_state() {
	unset prompt_impure_git_dirty prompt_impure_git_staging prompt_impure_git_arrows prompt_impure_git_fetch_pattern
	typeset -gA prompt_impure_worker_env=()
	typeset -gA prompt_impure_worker_env_pending=()
	typeset -gA prompt_impure_vcs_info
	prompt_impure_vcs_info[branch]=
	prompt_impure_vcs_info[top]=
	prompt_impure_vcs_info[action]=
	prompt_impure_vcs_info[pwd]=
}

prompt_impure_clear_jj_state() {
	typeset -g prompt_impure_jj_bookmark=
	typeset -g prompt_impure_jj_changeid=
	typeset -g prompt_impure_jj_working=
}

# Initialize gitstatusd for fast git status queries.
# Falls back gracefully if gitstatus is not installed.
prompt_impure_gitstatus_init() {
	(( ${prompt_impure_gitstatus_inited:-0} )) && return 0
	typeset -g prompt_impure_gitstatus_inited=0

	# Check if gitstatus plugin is available (sourced externally or via GITSTATUS_DIR).
	local gitstatus_plugin="${GITSTATUS_PLUGIN_ZSH:-}"
	if [[ -z "$gitstatus_plugin" ]]; then
		# Search common locations.
		local -a candidates=(
			"${GITSTATUS_DIR:-}/gitstatus.plugin.zsh"
			"${XDG_DATA_HOME:-$HOME/.local/share}/gitstatus/gitstatus.plugin.zsh"
			"/usr/share/gitstatus/gitstatus.plugin.zsh"
		)
		for gitstatus_plugin in "${candidates[@]}"; do
			[[ -r "$gitstatus_plugin" ]] && break
			gitstatus_plugin=
		done
	fi
	[[ -n "$gitstatus_plugin" && -r "$gitstatus_plugin" ]] || return 1

	# Use builtin source to avoid user-defined source() wrappers that may
	# leak positional parameters ($1 = filename) into the sourced script,
	# which breaks gitstatus.plugin.zsh's dynamic typeset on line 61.
	() {
		emulate -L zsh
		setopt no_xtrace
		builtin source "$gitstatus_plugin" 2>/dev/null
	} || return 1
	gitstatus_start -s -1 -u -1 -t 5 IMPURE 2>/dev/null || return 1
	prompt_impure_gitstatus_inited=1
	return 0
}

# Query git status via gitstatusd and populate impure's state variables.
# Returns 0 on success, 1 if not in a git repo or gitstatus unavailable.
prompt_impure_gitstatus_query() {
	(( ${prompt_impure_gitstatus_inited:-0} )) || return 1
	gitstatus_query -d "$PWD" IMPURE || return 1
	[[ "$VCS_STATUS_RESULT" == ok-sync || "$VCS_STATUS_RESULT" == ok-async ]] || return 1

	# Map VCS_STATUS_* to impure's internal state.
	typeset -gA prompt_impure_vcs_info
	prompt_impure_vcs_info[branch]="$VCS_STATUS_LOCAL_BRANCH"
	prompt_impure_vcs_info[top]="$VCS_STATUS_WORKDIR"
	prompt_impure_vcs_info[action]="$VCS_STATUS_ACTION"
	prompt_impure_vcs_info[pwd]="$PWD"

	# Dirty marker: only unstaged/untracked changes (matches git status --porcelain behavior).
	typeset -g prompt_impure_git_dirty=
	if (( VCS_STATUS_HAS_UNSTAGED || VCS_STATUS_HAS_UNTRACKED )); then
		prompt_impure_git_dirty="*"
	fi

	# Staging summary: (+added ~modified -deleted)
	local staging=""
	(( VCS_STATUS_NUM_STAGED_NEW )) && staging+="+${VCS_STATUS_NUM_STAGED_NEW} "
	local modified=$(( VCS_STATUS_NUM_STAGED - VCS_STATUS_NUM_STAGED_NEW - VCS_STATUS_NUM_STAGED_DELETED ))
	(( modified > 0 )) && staging+="~${modified} "
	(( VCS_STATUS_NUM_STAGED_DELETED )) && staging+="-${VCS_STATUS_NUM_STAGED_DELETED} "
	staging=${staging% }  # trim trailing space
	typeset -g prompt_impure_git_staging="${staging:-}"

	# Arrows: ahead/behind counts.
	typeset -g prompt_impure_git_arrows=
	local arrows=""
	(( VCS_STATUS_COMMITS_AHEAD )) && arrows+="⇡${VCS_STATUS_COMMITS_AHEAD}"
	(( VCS_STATUS_COMMITS_BEHIND )) && arrows+="⇣${VCS_STATUS_COMMITS_BEHIND}"
	prompt_impure_git_arrows="${arrows:-}"

	return 0
}

prompt_impure_async_init() {
	typeset -g prompt_impure_async_inited
	if ((${prompt_impure_async_inited:-0})); then
		return
	fi
	prompt_impure_async_inited=1
	# Initialize zsh-async library (deferred from setup for faster startup).
	async
	if ! async_start_worker "prompt_impure" -u -n 2>/dev/null; then
		# Worker failed to start (e.g. zpty permission denied).
		# Degrade gracefully by skipping async git operations.
		prompt_impure_async_inited=0
		return 1
	fi
	async_register_callback "prompt_impure" prompt_impure_async_callback
	async_worker_eval "prompt_impure" prompt_impure_async_renice
}

prompt_impure_async_tasks() {
	setopt localoptions noshwordsplit

	# If inside a jj repo, skip git entirely (jj takes precedence). Cache the
	# result per directory so we only walk the path on an actual `cd`, keeping
	# the synchronous precmd path off the filesystem in the common case.
	if [[ $PWD != ${prompt_impure_jj_repo_check_pwd:-} ]]; then
		typeset -g prompt_impure_jj_repo_check_pwd=$PWD
		if prompt_impure_in_jj_repo; then
			typeset -g prompt_impure_jj_repo_check=1
		else
			typeset -g prompt_impure_jj_repo_check=0
		fi
	fi
	if (( ${prompt_impure_jj_repo_check:-0} )); then
		prompt_impure_clear_git_state
		return
	fi

	# Check if git integration is enabled (default: yes).
	if ! zstyle -T ":prompt:impure:git" show; then
		if (( ${prompt_impure_async_inited:-0} )); then
			async_flush_jobs "prompt_impure"
		fi
		prompt_impure_clear_git_state
		return
	fi

	# Try gitstatusd first (fast path: single IPC call instead of 6 git forks).
	if (( ${prompt_impure_gitstatus_inited:-0} )) || prompt_impure_gitstatus_init; then
		if prompt_impure_gitstatus_query; then
			return
		fi
		# Not in a git repo — clear state and return.
		prompt_impure_clear_git_state
		return
	fi

	# Fallback: use zsh-async with individual git commands.
	if ! prompt_impure_async_init; then
		prompt_impure_clear_git_state
		return
	fi

	# Sync working directory and git environment variables to the async worker.
	# Skip if nothing changed since last sync (common case: running commands in same dir).
	# Uses an associative array to avoid scalar globals triggering AUTO_NAME_DIRS.
	typeset -gA prompt_impure_worker_env
	typeset -gA prompt_impure_worker_env_pending
	local cur_git_dir=${GIT_DIR-__unset__}
	local cur_git_work_tree=${GIT_WORK_TREE-__unset__}
	if [[ $PWD != ${prompt_impure_worker_env[pwd]-} ||
		$cur_git_dir != ${prompt_impure_worker_env[git_dir]-} ||
		$cur_git_work_tree != ${prompt_impure_worker_env[git_work_tree]-} ]]; then
		(( ${#prompt_impure_worker_env_pending} )) && return
		prompt_impure_clear_git_state
		async_flush_jobs "prompt_impure"
		typeset -gi prompt_impure_worker_sync_token
		(( prompt_impure_worker_sync_token++ ))
		local sync_token=$prompt_impure_worker_sync_token
		prompt_impure_worker_env_pending[pwd]=$PWD
		prompt_impure_worker_env_pending[git_dir]=$cur_git_dir
		prompt_impure_worker_env_pending[git_work_tree]=$cur_git_work_tree
		prompt_impure_worker_env_pending[token]=$sync_token
		async_worker_eval "prompt_impure" \
			prompt_impure_async_worker_sync $sync_token "$PWD" ${+GIT_DIR} "${GIT_DIR-}" ${+GIT_WORK_TREE} "${GIT_WORK_TREE-}" || {
				if [[ ${prompt_impure_worker_env_pending[token]-} == $sync_token ]]; then
					typeset -gA prompt_impure_worker_env_pending=()
				fi
				return
			}
		return
	fi

	typeset -gA prompt_impure_vcs_info

	local -H MATCH MBEGIN MEND
	if [[ $PWD != ${prompt_impure_vcs_info[pwd]}* ]]; then
		# Stop any running async jobs.
		async_flush_jobs "prompt_impure"

		# Reset preprompt variables, switching working tree.
		unset prompt_impure_git_dirty prompt_impure_git_staging
		unset prompt_impure_git_arrows
		unset prompt_impure_git_fetch_pattern
		prompt_impure_vcs_info[branch]=
		prompt_impure_vcs_info[top]=
	fi
	unset MATCH MBEGIN MEND

	async_job "prompt_impure" prompt_impure_async_vcs_info || return

	# Only perform tasks inside a Git working tree.
	[[ -n $prompt_impure_vcs_info[top] ]] || return

	prompt_impure_async_refresh
}

# Async jujutsu tasks: dispatch jj status check to the worker.
# Only runs when not inside a git repo (mutually exclusive with git).
prompt_impure_async_jj_tasks() {
	setopt localoptions noshwordsplit

	# Skip if jj integration is disabled.
	zstyle -T ":prompt:impure:jj" show || return

	# Git already skipped if .jj was found, so no need to check vcs_info here.

	# Ensure async worker is initialized.
	prompt_impure_async_init || return

	# Clear state and sync worker CWD on directory change.
	if [[ $PWD != ${prompt_impure_jj_pwd:-} ]]; then
		typeset -g prompt_impure_jj_pwd=$PWD
		prompt_impure_clear_jj_state
		async_flush_jobs "prompt_impure"
		# Sync the async worker's working directory so jj commands run in the
		# correct repo. Without this, the worker stays in its previous CWD
		# and prompt_impure_in_jj_repo fails to find .jj.
		async_worker_eval "prompt_impure" builtin cd -q ${(q)PWD}
	fi

	# Always dispatch: jj status can change without cd (e.g. jj commit, jj new).
	# The async worker handles concurrent job dedup internally.
	async_job "prompt_impure" prompt_impure_async_jj_status
}

prompt_impure_async_refresh() {
	setopt localoptions noshwordsplit

	if [[ -z $prompt_impure_git_fetch_pattern ]]; then
		# We set the pattern here to avoid redoing the pattern check until the
		# working tree has changed. Pull and fetch are always valid patterns.
		typeset -g prompt_impure_git_fetch_pattern="pull|fetch"
		async_job "prompt_impure" prompt_impure_async_git_aliases || return
	fi

	# Do not perform `git fetch` if it is disabled or in home folder.
	if (( ${IMPURE_GIT_PULL:-1} )) && [[ $prompt_impure_vcs_info[top] != $HOME ]]; then
		zstyle -t :prompt:impure:git:fetch only_upstream
		local only_upstream=$((? == 0))
		async_job "prompt_impure" prompt_impure_async_git_fetch $only_upstream || return
	else
		# Fetch is disabled or skipped; check arrows independently since
		# prompt_impure_async_git_fetch normally handles arrows after fetching.
		async_job "prompt_impure" prompt_impure_async_git_arrows || return
	fi

	# If dirty checking is sufficiently fast,
	# tell the worker to check it again, or wait for timeout.
	async_job "prompt_impure" prompt_impure_async_git_dirty ${IMPURE_GIT_UNTRACKED_DIRTY:-1} || return

}

prompt_impure_check_git_arrows() {
	setopt localoptions noshwordsplit
	local arrows left=${1:-0} right=${2:-0}

	(( left > 0 )) && arrows+="${IMPURE_GIT_UP_ARROW:-⇡}${left} "
	(( right > 0 )) && arrows+="${IMPURE_GIT_DOWN_ARROW:-⇣}${right} "
	arrows=${arrows% }  # trim trailing space

	[[ -n $arrows ]] || return
	typeset -g REPLY=$arrows
}

prompt_impure_async_callback() {
	setopt localoptions noshwordsplit
	local job=$1 code=$2 output=$3 exec_time=$4 next_pending=$6
	local do_render=0

	if [[ $job != '[async]' ]] &&
		(( ! ${prompt_impure_async_inited:-0} )); then
		return
	fi

	case $job in
		prompt_impure_async_vcs_info|prompt_impure_async_git_aliases|prompt_impure_async_git_dirty|prompt_impure_async_git_fetch|prompt_impure_async_git_arrows)
			[[ ${prompt_impure_worker_env[pwd]-} == $PWD ]] || return
			;;
	esac

	case $job in
		\[async])
			# Handle all the errors that could indicate a crashed
			# async worker. See zsh-async documentation for the
			# definition of the exit codes.
			if (( code == 2 )) || (( code == 3 )) || (( code == 130 )); then
				# Our worker died unexpectedly, try to recover immediately.
				typeset -g prompt_impure_async_inited=0
				async_stop_worker prompt_impure
				typeset -gA prompt_impure_worker_env=()
				typeset -gA prompt_impure_worker_env_pending=()
				if prompt_impure_async_init; then
					prompt_impure_async_tasks  # Restart all tasks.
				else
					prompt_impure_clear_git_state
					do_render=1
					next_pending=0
				fi

				# Reset render state due to restart.
				unset prompt_impure_async_render_requested
			fi
			;;
		\[async/eval])
			typeset -gA prompt_impure_worker_env_pending
			local worker_sync_output=${(M)${(f)output}:#prompt_impure_worker_sync:*}
			local -a worker_sync_result
			worker_sync_result=("${(@s.:.)worker_sync_output}")
			if [[ -n $worker_sync_output ]] &&
				(( ${#prompt_impure_worker_env_pending} )); then
				[[ $worker_sync_result[2] == ${prompt_impure_worker_env_pending[token]-} ]] || return
				local worker_sync_status=$worker_sync_result[3]
				if (( worker_sync_status )); then
					prompt_impure_clear_git_state
					do_render=1
					next_pending=0
				else
					typeset -gA prompt_impure_worker_env
					prompt_impure_worker_env[pwd]=$prompt_impure_worker_env_pending[pwd]
					prompt_impure_worker_env[git_dir]=$prompt_impure_worker_env_pending[git_dir]
					prompt_impure_worker_env[git_work_tree]=$prompt_impure_worker_env_pending[git_work_tree]
					typeset -gA prompt_impure_worker_env_pending=()
					prompt_impure_async_tasks
				fi
			elif (( code )); then
				# Looks like async_worker_eval failed,
				# rerun async tasks just in case.
				typeset -gA prompt_impure_worker_env=()
				typeset -gA prompt_impure_worker_env_pending=()
				prompt_impure_clear_git_state
				do_render=1
				next_pending=0
			fi
			;;
		prompt_impure_async_vcs_info)
			local -A info
			typeset -gA prompt_impure_vcs_info

			# Parse output (z) and unquote as array (Q@).
			info=("${(Q@)${(z)output}}")
			local -H MATCH MBEGIN MEND
			if [[ $info[pwd] != $PWD ]]; then
				# The path has changed since the check started, abort.
				return
			fi
			# Check if Git top-level has changed.
			if [[ $info[top] = $prompt_impure_vcs_info[top] ]]; then
				# If the stored pwd is part of $PWD, $PWD is shorter and likelier
				# to be top-level, so we update pwd.
				if [[ $prompt_impure_vcs_info[pwd] = ${PWD}* ]]; then
					prompt_impure_vcs_info[pwd]=$PWD
				fi
			else
				# Store $PWD to detect if we (maybe) left the Git path.
				prompt_impure_vcs_info[pwd]=$PWD
			fi
			unset MATCH MBEGIN MEND

			# The update has a Git top-level set, which means we just entered a new
			# Git directory. Run the async refresh tasks.
			[[ -n $info[top] ]] && [[ -z $prompt_impure_vcs_info[top] ]] && prompt_impure_async_refresh

			# Always update branch and top-level.
			prompt_impure_vcs_info[branch]=$info[branch]
			prompt_impure_vcs_info[top]=$info[top]
			prompt_impure_vcs_info[action]=$info[action]

			do_render=1
			;;
		prompt_impure_async_git_aliases)
			if [[ -n $output ]]; then
				# Append custom Git aliases to the predefined ones.
				prompt_impure_git_fetch_pattern+="|$output"
			fi
			;;
		prompt_impure_async_git_dirty)
			local prev_staging=$prompt_impure_git_staging
			local prev_dirty=$prompt_impure_git_dirty
			if (( code == 0 )); then
				unset prompt_impure_git_staging
				unset prompt_impure_git_dirty
			else
				# Parse: "staging|working" (e.g. "+2 ~1|*" or "|*" or "+1|")
				local staging_part=${output%%|*}
				local working_part=${output#*|}
				typeset -g prompt_impure_git_staging="$staging_part"
				typeset -g prompt_impure_git_dirty="$working_part"
			fi

			[[ $prev_staging != ${prompt_impure_git_staging:-} || $prev_dirty != ${prompt_impure_git_dirty:-} ]] && do_render=1

			;;
		prompt_impure_async_git_fetch|prompt_impure_async_git_arrows)
			# `prompt_impure_async_git_fetch` executes `prompt_impure_async_git_arrows`
			# after a successful fetch.
			case $code in
				0)
					local REPLY
					prompt_impure_check_git_arrows ${(ps:\t:)output}
					if [[ $prompt_impure_git_arrows != $REPLY ]]; then
						typeset -g prompt_impure_git_arrows=$REPLY
						do_render=1
					fi
					;;
				97)
					# No remote available, make sure to clear git arrows if set.
					if [[ -n $prompt_impure_git_arrows ]]; then
						typeset -g prompt_impure_git_arrows=
						do_render=1
					fi
					;;
				99|98)
					# Git fetch failed.
					;;
				*)
					# Non-zero exit status from `prompt_impure_async_git_arrows`,
					# indicating that there is no upstream configured.
					if [[ -n $prompt_impure_git_arrows ]]; then
						unset prompt_impure_git_arrows
						do_render=1
					fi
					;;
			esac
			;;

		prompt_impure_async_jj_status)
			local prev_bookmark=$prompt_impure_jj_bookmark
			local prev_changeid=$prompt_impure_jj_changeid
			local prev_working=$prompt_impure_jj_working
			if (( code == 0 )); then
				# Parse: "bookmark(s)|changeID working_changes"
				# Split on | to separate bookmarks from changeID+working.
				local before_pipe after_pipe
				before_pipe=${output%%|*}
				after_pipe=${output#*|}
				typeset -g prompt_impure_jj_bookmark="${before_pipe%% }"
				# First token after | is the change ID, rest is working changes.
				local -a after_parts
				after_parts=(${=after_pipe})
				typeset -g prompt_impure_jj_changeid="${after_parts[1]:-}"
				typeset -g prompt_impure_jj_working="${(j: :)after_parts[2,-1]}"
			else
				typeset -g prompt_impure_jj_bookmark=
				typeset -g prompt_impure_jj_changeid=
				typeset -g prompt_impure_jj_working=
			fi
			[[ $prev_bookmark != $prompt_impure_jj_bookmark || $prev_changeid != $prompt_impure_jj_changeid || $prev_working != $prompt_impure_jj_working ]] && do_render=1
			;;
	esac

	if (( next_pending )); then
		(( do_render )) && typeset -g prompt_impure_async_render_requested=1
		return
	fi

	[[ ${prompt_impure_async_render_requested:-$do_render} = 1 ]] && prompt_impure_preprompt_render
	unset prompt_impure_async_render_requested
}

prompt_impure_reset_prompt() {
	if [[ $CONTEXT == cont ]]; then
		# When the context is "cont", PS2 is active and calling
		# reset-prompt will have no effect on PS1, but it will
		# reset the execution context (%_) of PS2 which we don't
		# want. Unfortunately, we can't save the output of "%_"
		# either because it is only ever rendered as part of the
		# prompt, expanding in-place won't work.
		return
	fi

	zle && zle .reset-prompt
}

prompt_impure_reset_prompt_symbol() {
	prompt_impure_state[prompt]=${IMPURE_PROMPT_SYMBOL:-❯}
}

prompt_impure_update_vim_prompt_widget() {
	setopt localoptions noshwordsplit
	prompt_impure_state[prompt]=${${${KEYMAP/vicmd/${IMPURE_PROMPT_VICMD_SYMBOL:-❮}}/visual/${IMPURE_PROMPT_VICMD_SYMBOL:-❮}}/(main|viins)/${IMPURE_PROMPT_SYMBOL:-❯}}

	prompt_impure_reset_prompt
}

prompt_impure_reset_vim_prompt_widget() {
	setopt localoptions noshwordsplit
	prompt_impure_reset_prompt_symbol

	# We can't perform a prompt reset at this point because it
	# removes the prompt marks inserted by macOS Terminal.
}

# Transient prompt: after Enter, replace the two-line prompt with just ❯.
# We wrap accept-line to set a flag, then use zle redisplay in line-finish
# to rewrite the prompt area before zsh commits it to scrollback.
prompt_impure_accept_line() {
	typeset -g prompt_impure_transient=1
	zle .accept-line
}

prompt_impure_transient_redraw() {
	setopt localoptions noshwordsplit

	(( ${prompt_impure_transient:-0} )) || return
	unset prompt_impure_transient

	local prompt_color
	prompt_color=$prompt_impure_colors[prompt:success]

	# Save full prompt, swap to minimal, redraw.
	typeset -g prompt_impure_saved_prompt="$PROMPT"
	typeset -g prompt_impure_saved_rprompt="$RPROMPT"
	PROMPT="%F{${prompt_color}}${IMPURE_PROMPT_SYMBOL:-❯}%f "
	RPROMPT=
	zle && zle .reset-prompt && zle -R
}


prompt_impure_state_setup() {
	setopt localoptions noshwordsplit

	# Check SSH_CONNECTION and the current state.
	local ssh_connection=${SSH_CONNECTION:-$PROMPT_IMPURE_SSH_CONNECTION}
	local username hostname
	if [[ -z $ssh_connection ]] && (( $+commands[who] )); then
		# When changing user on a remote system, the $SSH_CONNECTION
		# environment variable can be lost. Attempt detection via `who`.
		# Only try who -m; skip fallback to plain `who` which is slow on macOS.
		local who_out
		who_out=$(who -m 2>/dev/null) || true

		local reIPv6='(([0-9a-fA-F]+:)|:){2,}[0-9a-fA-F]+'
		local reIPv4='([0-9]{1,3}\.){3}[0-9]+'
		local reHostname='([.][^. ]+){2}'

		local -H MATCH MBEGIN MEND
		if [[ -n $who_out ]] && [[ $who_out =~ "\(?($reIPv4|$reIPv6|$reHostname)\)?\$" ]]; then
			ssh_connection=$MATCH
			export PROMPT_IMPURE_SSH_CONNECTION=$ssh_connection
		fi
		unset MATCH MBEGIN MEND
	fi

	local user_color
	# Show `username@host` if logged in through SSH.
	[[ -n $ssh_connection ]] && user_color=user

	# Show `username@host` if inside a container and not in GitHub Codespaces.
	[[ -z "${CODESPACES}" ]] && prompt_impure_is_inside_container && user_color=user

	# Show `username@host` if root, with username in default color.
	[[ $UID -eq 0 ]] && user_color=user:root

	# Set psvar[13] flag for username display in PROMPT.
	[[ -n $user_color ]] && psvar[13]=1

	# Check if hostname display is enabled (default: yes).
	local show_host=1
	zstyle -T ":prompt:impure:host" show || show_host=0

	typeset -gA prompt_impure_state
	prompt_impure_state[version]="0.1.0"
	prompt_impure_state+=(
		user_color "$user_color"
		show_host  "$show_host"
		prompt     "${IMPURE_PROMPT_SYMBOL:-❯}"
	)
}

# Return true if executing inside a Docker, OCI, LXC, or systemd-nspawn container.
prompt_impure_is_inside_container() {
	local -r nspawn_file='/run/host/container-manager'
	local -r podman_crio_file='/run/.containerenv'
	local -r docker_file='/.dockerenv'
	local -r k8s_token_file='/var/run/secrets/kubernetes.io/serviceaccount/token'
	local -r cgroup_file='/proc/1/cgroup'
	[[ "$container" == "lxc" ]] \
		|| [[ "$container" == "oci" ]] \
		|| [[ "$container" == "podman" ]] \
		|| [[ -r "$nspawn_file" ]] \
		|| [[ -r "$podman_crio_file" ]] \
		|| [[ -r "$docker_file" ]] \
		|| [[ -r "$k8s_token_file" ]] \
		|| [[ -r "$cgroup_file" && "$(< $cgroup_file)" = *(lxc|docker|containerd)* ]]
}

prompt_impure_system_report() {
	setopt localoptions noshwordsplit

	local shell=$SHELL
	if [[ -z $shell ]]; then
		shell=$commands[zsh]
	fi
	print - "- Zsh: $($shell --version) ($shell)"
	print -n - "- Operating system: "
	case "$(uname -s)" in
		Darwin)	print "$(sw_vers -productName) $(sw_vers -productVersion) ($(sw_vers -buildVersion))";;
		*)	print "$(uname -s) ($(uname -r) $(uname -v) $(uname -m) $(uname -o))";;
	esac
	print - "- Terminal program: ${TERM_PROGRAM:-unknown} (${TERM_PROGRAM_VERSION:-unknown})"
	print -n - "- Tmux: "
	[[ -n $TMUX ]] && print "yes" || print "no"

	local git_version
	git_version=($(git --version))  # Remove newlines, if hub is present.
	print - "- Git: $git_version"

	print - "- Impure state:"
	for k v in "${(@kv)prompt_impure_state}"; do
		print - "    - $k: \`${(q-)v}\`"
	done
	print - "- zsh-async version: \`${ASYNC_VERSION}\`"
	print - "- PROMPT: \`$(typeset -p PROMPT)\`"
	print - "- Colors: \`$(typeset -p prompt_impure_colors)\`"
	print - "- TERM: \`$(typeset -p TERM)\`"
	print - "- Virtualenv: \`$(typeset -p VIRTUAL_ENV_DISABLE_PROMPT)\`"


	local ohmyzsh=0
	typeset -la frameworks
	(( $+ANTIBODY_HOME )) && frameworks+=("Antibody")
	(( $+ADOTDIR )) && frameworks+=("Antigen")
	(( $+ANTIGEN_HS_HOME )) && frameworks+=("Antigen-hs")
	(( $+functions[upgrade_oh_my_zsh] )) && {
		ohmyzsh=1
		frameworks+=("Oh My Zsh")
	}
	(( $+ZPREZTODIR )) && frameworks+=("Prezto")
	(( $+ZPLUG_ROOT )) && frameworks+=("Zplug")
	(( $+ZPLGM )) && frameworks+=("Zplugin")

	(( $#frameworks == 0 )) && frameworks+=("None")
	print - "- Detected frameworks: ${(j:, :)frameworks}"

	if (( ohmyzsh )); then
		print - "    - Oh My Zsh:"
		print - "        - Plugins: ${(j:, :)plugins}"
	fi
}

prompt_impure_preview() {
	setopt localoptions noshwordsplit

	prompt_impure_set_colors

	local -A c=("${(@kv)prompt_impure_colors}")

	local path_sample="%F{$c[path]}~/dev/impure%f"
	if zstyle -t ':prompt:impure:path:separator' dim; then
		path_sample=$(prompt_impure_render_dimmed_path '~/dev/impure')
	fi

	local host_sample=''
	if zstyle -T ":prompt:impure:host" show; then
		host_sample="%F{$c[host]}@heartofgold%f"
	fi

	# Sample prompt with all components visible.
	# Left side: info segments. Right side (RPROMPT): exec time + nix shell + symbol.
	print -P "%F{$c[custom:prefix]}prefix%f %F{$c[suspended_jobs]}${IMPURE_SUSPENDED_JOBS_SYMBOL-✦}%f %F{$c[user]}zaphod%f${host_sample} %F{$c[zmx]}[zmx]%f ${path_sample} %F{$c[git:branch]}main%f%F{$c[git:dirty]}*%f %F{$c[git:action]}rebase-i%f %F{$c[git:arrow]}${IMPURE_GIT_UP_ARROW:-⇡}2 ${IMPURE_GIT_DOWN_ARROW:-⇣}1%f %F{$c[custom:suffix]}suffix%f"
	print -P "  ← left side above | right side below →"
	print -P "%F{$c[execution_time]}42s%f %F{$c[nix-shell]}pure%f %F{$c[prompt:success]}${IMPURE_PROMPT_SYMBOL:-❯}%f"
	print
	print -P "%F{$c[prompt:error]}${IMPURE_PROMPT_SYMBOL:-❯}%f  prompt after error"
	print; print
	print; print
	print -P "%F{$c[user:root]}root%f${host_sample}  root user"
	print; print
	print -P "%F{$c[prompt:continuation]}… if%f %F{$c[prompt:success]}${IMPURE_PROMPT_SYMBOL:-❯}%f  continuation prompt"
}

# Build RPROMPT string from current psvar state.
prompt_impure_build_rprompt() {
	setopt localoptions noshwordsplit

	RPROMPT=''
	# Execution time (only if above threshold).
	RPROMPT+='%(20V.%F{$prompt_impure_colors[execution_time]}%20v%f.)'
	# Nix shell type indicator.
	RPROMPT+='%(21V. %F{$prompt_impure_colors[nix-shell]}%21v%f.)'
}

prompt_impure_setup() {
	# Show a marker when command output doesn't end with a newline.
	export PROMPT_EOL_MARK='%B%S%#%s%b'

	prompt_opts=(subst percent)

	# Borrowed from `promptinit`. Sets the prompt options in case Impure was not
	# initialized via `promptinit`.
	setopt noprompt{bang,cr,percent,subst} "prompt${^prompt_opts[@]}"

	# Enable bracketed paste mode permanently (prevents accidental execution of pasted text).
	print -rn -- $'\e[?2004h'

	if [[ -z $prompt_newline ]]; then
		# This variable needs to be set, usually set by promptinit.
		typeset -g prompt_newline=$'\n%{\r%}'
	fi

	zmodload zsh/datetime
	zmodload zsh/zle
	zmodload zsh/parameter
	zmodload zsh/zutil

	autoload -Uz add-zsh-hook
	autoload -Uz vcs_info
	autoload -Uz async

	# The `add-zle-hook-widget` function is not guaranteed to be available.
	# It was added in Zsh 5.3.
	autoload -Uz +X add-zle-hook-widget 2>/dev/null

	# Set the colors.
	typeset -gA prompt_impure_colors_default prompt_impure_colors
	prompt_impure_colors_default=(
		custom:prefix        242
		custom:suffix        242
		execution_time       yellow
		git:arrow            cyan
		git:branch           242
		git:action           yellow
		git:dirty            242
		host                 242
		jj                   242
		nix-shell            red
		path                 blue
		prompt:error         red
		prompt:success       magenta
		prompt:ssh           yellow
		prompt:continuation  242
		suspended_jobs       red
		user                 242
		user:root            default
		virtualenv           242
		zmx                  green
	)
	prompt_impure_colors=("${(@kv)prompt_impure_colors_default}")

	add-zsh-hook precmd prompt_impure_precmd
	add-zsh-hook preexec prompt_impure_preexec

	prompt_impure_state_setup

	zle -N prompt_impure_reset_prompt
	zle -N prompt_impure_update_vim_prompt_widget
	zle -N prompt_impure_reset_vim_prompt_widget
	zle -N prompt_impure_accept_line
	zle -N prompt_impure_transient_redraw
	if (( $+functions[add-zle-hook-widget] )); then
		add-zle-hook-widget zle-line-finish prompt_impure_reset_vim_prompt_widget
		add-zle-hook-widget zle-keymap-select prompt_impure_update_vim_prompt_widget
		add-zle-hook-widget zle-line-finish prompt_impure_transient_redraw
	fi

	# Bind accept-line to our wrapper so we can set the transient flag.
	bindkey '^M' prompt_impure_accept_line
	bindkey '^J' prompt_impure_accept_line

	# Initialize git globals referenced by PROMPT via prompt subst.
	typeset -gA prompt_impure_vcs_info
	typeset -g prompt_impure_git_branch_color=$prompt_impure_colors[git:branch]

	# Initialize jj globals.
	typeset -g prompt_impure_jj_bookmark=
	typeset -g prompt_impure_jj_changeid=
	typeset -g prompt_impure_jj_working=
	typeset -g prompt_impure_jj_pwd=
	typeset -g prompt_impure_jj_repo_check_pwd=
	typeset -g prompt_impure_jj_repo_check=0

	# Construct PROMPT once, both preprompt and prompt line. Kept
	# dynamic via variables and psvar[12-27], updated each render
	# in prompt_impure_preprompt_render. Numbering starts at 12 for
	# legacy reasons (Pure originally used psvar[12] for virtualenv)
	# and to avoid collisions with low psvar indices which users
	# may rely on (e.g. %v expands psvar[1]).
	#
	#   psvar[12] = suspended jobs symbol (e.g. ✦)
	#   psvar[13] = username flag, renders user/host (e.g. user@host)
	#   psvar[14] = git branch
	#   psvar[15] = git staging summary (e.g. "+2 ~1"), shown in (parens)
	#   psvar[16] = git working tree dirty marker ("*")
	#   psvar[17] = git action (e.g. rebase, merge)
	#   psvar[18] = git arrows with counts (e.g. ⇡1 ⇣3)
	#   psvar[20] = exec time (e.g. 1d 3h 2m 5s) — shown in RPROMPT
	#   psvar[21] = virtualenv/nix-shell name — shown in RPROMPT
	#   psvar[22] = custom prefix (set by prompt_impure_precustom)
	#   psvar[23] = custom suffix (set by prompt_impure_precustom)
	#   psvar[24] = ZMX session tag (e.g. [session-name])
	#   psvar[25] = Jujutsu bookmark(s)
	#   psvar[26] = Jujutsu change ID (cyan)
	#   psvar[27] = Jujutsu working set changes
	#
	# Example output:
	#   hostname [zmx] ~/Code/impure main (+2 ~1)* rebase ⇣⇡ ≡ suffix
	#   42s pure ❯
	#
	# Preprompt line: each %(NV..) section only renders when its psvar is non-empty.
	PROMPT='${prompt_newline}'
	PROMPT+='%(13V.%F{$prompt_impure_colors[prompt:ssh]}%m%f .)'
	PROMPT+='%(24V.%F{$prompt_impure_colors[zmx]}%24v%f .)'
	prompt_impure_set_path_separator
	PROMPT+='${${prompt_impure_path_separator_dimmed:+$(prompt_impure_render_dimmed_path)}:-${prompt_impure_path_segment}}'
	# Git: branch + staging summary + dirty marker + arrows (oh-my-posh style)
	PROMPT+='%(14V. %F{${prompt_impure_git_branch_color}}%14v%f.)'
	PROMPT+='%(15V.%F{$prompt_impure_colors[git:dirty]} (%15v)%f.)'
	PROMPT+='%(16V.%F{$prompt_impure_colors[git:dirty]}%16v%f.)'
	PROMPT+='%(17V. %F{$prompt_impure_colors[git:action]}%17v%f.)'
	PROMPT+='%(18V. %F{cyan}%18v%f.)'

	# Jujutsu: bookmark (grey) + @changeID (cyan) + working changes (grey)
	PROMPT+='%(25V. %F{$prompt_impure_colors[jj]}%25v%f.)'
	PROMPT+='%(26V. %F{cyan}@%26v%f.)'
	PROMPT+='%(27V. %F{$prompt_impure_colors[jj]}%27v%f.)'
	PROMPT+='%(22V. %F{$prompt_impure_colors[custom:prefix]}%22v%f.)'
	PROMPT+='%(23V. %F{$prompt_impure_colors[custom:suffix]}%23v%f.)'

	# Newline before the prompt symbol.
	PROMPT+='${prompt_newline}'
	# Prompt symbol: magenta locally, red on error.
	PROMPT+='%(?.%F{$prompt_impure_colors[prompt:success]}.%F{$prompt_impure_colors[prompt:error]})${prompt_impure_state[prompt]}%f '

	# Indicate continuation prompt by … and use a darker color for it.
	PROMPT2='%F{$prompt_impure_colors[prompt:continuation]}… %(1_.%_ .%_)%f%(?.%F{$prompt_impure_colors[prompt:success]}.%F{$prompt_impure_colors[prompt:error]})${prompt_impure_state[prompt]}%f '

	# Build right prompt.
	prompt_impure_build_rprompt

	# Store prompt expansion symbols for in-place expansion via (%). For
	# some reason it does not work without storing them in a variable first.
	typeset -ga prompt_impure_debug_depth
	prompt_impure_debug_depth=('%e' '%N' '%x')

	# Compare is used to check if %N equals %x. When they differ, the main
	# prompt is used to allow displaying both filename and function. When
	# they match, we use the secondary prompt to avoid displaying duplicate
	# information.
	local -A ps4_parts
	ps4_parts=(
		depth 	  '%F{yellow}${(l:${(%)prompt_impure_debug_depth[1]}::+:)}%f'
		compare   '${${(%)prompt_impure_debug_depth[2]}:#${(%)prompt_impure_debug_depth[3]}}'
		main      '%F{blue}${${(%)prompt_impure_debug_depth[3]}:t}%f%F{242}:%I%f %F{242}@%f%F{blue}%N%f%F{242}:%i%f'
		secondary '%F{blue}%N%f%F{242}:%i'
		prompt 	  '%F{242}>%f '
	)
	# Combine the parts with conditional logic. First the `:+` operator is
	# used to replace `compare` either with `main` or an empty string. Then
	# the `:-` operator is used so that if `compare` becomes an empty
	# string, it is replaced with `secondary`.
	local ps4_symbols='${${'${ps4_parts[compare]}':+"'${ps4_parts[main]}'"}:-"'${ps4_parts[secondary]}'"}'

	# Improve the debug prompt (PS4), show depth by repeating the +-sign and
	# add colors to highlight essential parts like file and function name.
	PROMPT4="${ps4_parts[depth]} ${ps4_symbols}${ps4_parts[prompt]}"

	# Guard against Oh My Zsh themes overriding Impure.
	unset ZSH_THEME

	# Guard against (ana)conda changing the PS1 prompt
	# (we manually insert the env when it's available).

	# Guard against pyenv-virtualenv changing the PS1 prompt
	# (we manually insert the env when it's available).
	export PYENV_VIRTUALENV_DISABLE_PROMPT=1
}

prompt_impure_setup "$@"
