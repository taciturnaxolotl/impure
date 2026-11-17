# Impure
# Forked from Pure by Sindre Sorhus
# https://github.com/sindresorhus/pure
# MIT License

# Git and jj status live in vcs.zsh, next to this file.
source "${${(%):-%x}:A:h}/vcs.zsh"

# Store the last command's run time, as "1d 21h 56m 32s" or "1.23s", in
# prompt_impure_cmd_exec_time once it passes IMPURE_CMD_MAX_EXEC_TIME.
prompt_impure_check_cmd_exec_time() {
	local -F elapsed=$(( EPOCHREALTIME - ${prompt_impure_cmd_timestamp:-$EPOCHREALTIME} ))
	typeset -g prompt_impure_cmd_exec_time=
	(( elapsed >= ${IMPURE_CMD_MAX_EXEC_TIME:-3} )) || return 0

	local -i days=$(( elapsed / 86400 )) hours=$(( elapsed / 3600 % 24 )) minutes=$(( elapsed / 60 % 60 ))
	local formatted=
	(( days )) && formatted+="${days}d "
	(( hours )) && formatted+="${hours}h "
	(( minutes )) && formatted+="${minutes}m "
	if (( days || hours || minutes )); then
		local -i whole=elapsed
		formatted+="$(( whole % 60 ))s"
	else
		printf -v formatted '%.2fs' $elapsed
	fi
	prompt_impure_cmd_exec_time=$formatted
}

prompt_impure_set_title() {
	setopt localoptions noshwordsplit

	zstyle -T ":prompt:impure:title" show || return
	# Emacs terminals can't set the title, and serial consoles shouldn't.
	(( ${+EMACS} || ${+INSIDE_EMACS} )) && return
	[[ $TTY == /dev/ttyS[0-9]* ]] && return

	# Expand the hostname in place in case ignore-escape is used.
	local hostname=
	(( psvar[13] )) && hostname="${(%):-(%m) }"

	local -a opts
	case $1 in
		expand-prompt) opts=(-P);;
		ignore-escape) opts=(-r);;
	esac

	# One print, so the title survives XTRACE.
	print -n $opts $'\e]0;'${hostname}${2}$'\a'
}

prompt_impure_preexec() {
	# Cancel our background fetch when the user runs a pull or fetch (or an
	# alias for one), so the two don't collide.
	local -H MATCH MBEGIN MEND match mbegin mend
	if [[ -n $prompt_impure_git_fetch_pattern && $2 =~ (git|hub)\ (.*\ )?($prompt_impure_git_fetch_pattern)(\ .*)?$ ]]; then
		async_flush_jobs 'prompt_impure'
	fi

	typeset -gF prompt_impure_cmd_timestamp=$EPOCHREALTIME

	prompt_impure_set_title 'ignore-escape' "$PWD:t: $2"

	# Keep virtualenv off the prompt; 20 marks it as Impure's doing (see precmd).
	export VIRTUAL_ENV_DISABLE_PROMPT=${VIRTUAL_ENV_DISABLE_PROMPT:-20}
}

# Pick up colors and the path style from zstyle.
prompt_impure_set_colors() {
	local color key value
	for key value in ${(kv)prompt_impure_colors}; do
		zstyle -t ":prompt:impure:$key" color "$value" && continue
		case $? in
			1) zstyle -s ":prompt:impure:$key" color color
				prompt_impure_colors[$key]=$color ;;
			2) prompt_impure_colors[$key]=$prompt_impure_colors_default[$key] ;;
		esac
	done

	# Expanded through ${(e)...} in PROMPT. The dimmed form escapes %, swaps
	# every / for a dimmed one and keeps a leading / bright, all without a fork.
	if zstyle -t ':prompt:impure:path:separator' dim; then
		typeset -g prompt_impure_path_segment='%F{$prompt_impure_colors[path]}${${${${(%):-%~}//\%/%%}//\//$prompt_impure_path_sep_dim}/#$prompt_impure_path_sep_dim//}%f'
	else
		typeset -g prompt_impure_path_segment='%F{$prompt_impure_colors[path]}%~%f'
	fi
}

# Copy state into psvar (see the table in prompt_impure_setup) and redraw if
# anything visible changed.
prompt_impure_preprompt_render() {
	setopt localoptions noshwordsplit

	unset prompt_impure_async_render_requested

	psvar[12]=
	(( ${(M)#jobstates:#suspended:*} )) && psvar[12]=${IMPURE_SUSPENDED_JOBS_SYMBOL-✦}
	psvar[14]=$prompt_impure_vcs_info[branch]
	psvar[15]=$prompt_impure_git_staging
	psvar[16]=$prompt_impure_git_dirty
	psvar[17]=$prompt_impure_vcs_info[action]
	psvar[18]=$prompt_impure_git_arrows
	psvar[20]=$prompt_impure_cmd_exec_time
	psvar[22]= psvar[23]=
	(( $+functions[prompt_impure_precustom] )) && prompt_impure_precustom
	psvar[24]=${ZMX_SESSION:+[$ZMX_SESSION]}
	psvar[25]=$prompt_impure_jj_bookmark
	psvar[26]=$prompt_impure_jj_changeid
	psvar[27]=$prompt_impure_jj_working
	psvar[28]=$prompt_impure_git_detached
	psvar[29]=${prompt_impure_git_conflicted:-$prompt_impure_jj_conflicted}

	# Compare state instead of expanding PROMPT. Exec time is left out: only
	# precmd changes it, and precmd never redraws.
	local fingerprint="${(pj:\0:)psvar[12,19]}${(pj:\0:)psvar[21,29]}"$'\0'"$prompt_impure_state[prompt]"$'\0'"$PWD"
	if [[ $1 != precmd && $prompt_impure_last_prompt != $fingerprint ]]; then
		prompt_impure_reset_prompt
	fi
	typeset -g prompt_impure_last_prompt=$fingerprint
}

# Undo instant-prompt.zsh: restore the terminal fds, clear the placeholder and
# replay whatever init printed meanwhile.
prompt_impure_instant_prompt_cleanup() {
	(( ${IMPURE_INSTANT_PROMPT_ACTIVE:-0} )) || return 0
	typeset -g IMPURE_INSTANT_PROMPT_ACTIVE=0
	if (( ${IMPURE_IP_FD_1:-0} )) && { true >&${IMPURE_IP_FD_1} } 2>/dev/null; then
		exec 0<&${IMPURE_IP_FD_0} 1>&${IMPURE_IP_FD_1} 2>&${IMPURE_IP_FD_2} \
			{IMPURE_IP_FD_0}>&- {IMPURE_IP_FD_1}>&- {IMPURE_IP_FD_2}>&-
	fi
	zmodload zsh/terminfo 2>/dev/null
	print -rn -- "${terminfo[rc]:-$'\e8'}${terminfo[ed]:-$'\e[J'}"
	[[ -s ${IMPURE_IP_OUTPUT_FILE:-} ]] && cat "$IMPURE_IP_OUTPUT_FILE" 2>/dev/null
	rm -f "${IMPURE_IP_OUTPUT_FILE:-}" 2>/dev/null
	unset IMPURE_IP_FD_0 IMPURE_IP_FD_1 IMPURE_IP_FD_2 IMPURE_IP_OUTPUT_FILE
	prompt_impure_reset_prompt
}

# Put back the full prompt after a transient collapse.
prompt_impure_restore_prompt() {
	[[ -n ${prompt_impure_saved_prompt:-} ]] || return 0
	PROMPT=$prompt_impure_saved_prompt
	RPROMPT=$prompt_impure_saved_rprompt
	unset prompt_impure_saved_prompt prompt_impure_saved_rprompt
}

prompt_impure_precmd() {
	setopt localoptions noshwordsplit

	prompt_impure_instant_prompt_cleanup

	prompt_impure_check_cmd_exec_time
	unset prompt_impure_cmd_timestamp

	prompt_impure_set_title 'expand-prompt' '%~'
	prompt_impure_set_colors
	prompt_impure_restore_prompt

	prompt_impure_vcs_tasks

	# psvar[21]: virtualenv or nix shell. An empty VIRTUAL_ENV_DISABLE_PROMPT
	# means the user unset it, so Impure takes back control.
	psvar[21]=
	if zstyle -T ":prompt:impure:environment:virtualenv" show &&
		[[ -n $VIRTUAL_ENV && ( -z $VIRTUAL_ENV_DISABLE_PROMPT || $VIRTUAL_ENV_DISABLE_PROMPT == 20 ) ]]; then
		psvar[21]=${VIRTUAL_ENV_PROMPT:-${VIRTUAL_ENV:t}}
		export VIRTUAL_ENV_DISABLE_PROMPT=20
	fi
	if zstyle -T ":prompt:impure:environment:nix-shell" show && [[ -n $IN_NIX_SHELL ]]; then
		psvar[21]=impure
	fi

	prompt_impure_reset_prompt_symbol
	prompt_impure_preprompt_render precmd

	# Separate prompts from command output, but not the very first prompt.
	if (( ${prompt_impure_first_precmd_done:-0} )); then
		typeset -g prompt_impure_newline=$prompt_newline
	else
		typeset -g prompt_impure_first_precmd_done=1
	fi
}

prompt_impure_reset_prompt() {
	# In a continuation (PS2), reset-prompt can't touch PS1 and would wipe %_.
	[[ $CONTEXT == cont ]] && return
	zle && zle .reset-prompt
}

# Also the zle-line-finish widget; resetting the prompt there would remove
# the prompt marks macOS Terminal inserts.
prompt_impure_reset_prompt_symbol() {
	prompt_impure_state[prompt]=${IMPURE_PROMPT_SYMBOL:-❯}
}

prompt_impure_update_vim_prompt_widget() {
	case $KEYMAP in
		vicmd|visual) prompt_impure_state[prompt]=${IMPURE_PROMPT_VICMD_SYMBOL:-❮} ;;
		*) prompt_impure_state[prompt]=${IMPURE_PROMPT_SYMBOL:-❯} ;;
	esac
	prompt_impure_reset_prompt
}

# Transient prompt, part one: Enter on a complete line marks the next
# zle-line-finish to collapse the prompt.
prompt_impure_accept_line() {
	[[ $CONTEXT != cont ]] && typeset -g prompt_impure_transient=1
	# Not .accept-line, so wrappers from other plugins still run.
	zle accept-line
}

# Transient prompt, part two (zle-line-finish): collapse to a bare symbol
# before the line goes to scrollback. precmd restores the saved prompt.
prompt_impure_transient_redraw() {
	(( ${prompt_impure_transient:-0} )) || return
	unset prompt_impure_transient

	typeset -g prompt_impure_saved_prompt=$PROMPT prompt_impure_saved_rprompt=$RPROMPT
	PROMPT="%F{$prompt_impure_colors[$prompt_impure_state[prompt_color]]}${IMPURE_PROMPT_SYMBOL:-❯}%f "
	RPROMPT=
	if zle; then
		POSTDISPLAY=
		zle .reset-prompt
		zle -R
	fi
}

prompt_impure_clear_screen() {
	# No leading newline above the first prompt after a clear.
	typeset -g prompt_impure_newline=
	zle .clear-screen
	typeset -g prompt_impure_newline=$prompt_newline
}

prompt_impure_state_setup() {
	setopt localoptions noshwordsplit

	# $SSH_CONNECTION is lost when switching users on a remote host, so fall
	# back to `who -m` (plain `who` is slow on macOS).
	local ssh_connection=${SSH_CONNECTION:-${PROMPT_IMPURE_SSH_CONNECTION-}}
	if [[ -z $ssh_connection ]] && (( $+commands[who] )); then
		local who_out
		who_out=$(who -m 2>/dev/null)
		local reIPv6='(([0-9a-fA-F]+:)|:){2,}[0-9a-fA-F]+'
		local reIPv4='([0-9]{1,3}\.){3}[0-9]+'
		local reHostname='([.][^. ]+){2}'
		local -H MATCH MBEGIN MEND
		if [[ $who_out =~ "\(?($reIPv4|$reIPv6|$reHostname)\)?\$" ]]; then
			ssh_connection=$MATCH
			export PROMPT_IMPURE_SSH_CONNECTION=$ssh_connection
		fi
	fi

	# psvar[13]: show the hostname over SSH, in a container (not Codespaces)
	# or as root, unless hidden.
	psvar[13]=
	if zstyle -T ":prompt:impure:host" show &&
		{ [[ -n $ssh_connection || $UID -eq 0 ]] ||
			{ [[ -z ${CODESPACES-} ]] && prompt_impure_is_inside_container } }; then
		psvar[13]=1
	fi

	# prompt_color names a color key, so zstyle overrides still apply.
	typeset -gA prompt_impure_state=(
		prompt       ${IMPURE_PROMPT_SYMBOL:-❯}
		prompt_color prompt:success
	)
	if [[ -n $ssh_connection ]]; then
		prompt_impure_state[prompt_color]=prompt:ssh
	fi
}

# Docker, OCI, Podman, LXC, systemd-nspawn or Kubernetes.
prompt_impure_is_inside_container() {
	[[ ${container-} == (lxc|oci|podman) ]] ||
		[[ -r /run/host/container-manager || -r /run/.containerenv || -r /.dockerenv ]] ||
		[[ -r /var/run/secrets/kubernetes.io/serviceaccount/token ]] ||
		[[ -r /proc/1/cgroup && $(</proc/1/cgroup) == *(lxc|docker|containerd)* ]]
}

prompt_impure_system_report() {
	setopt localoptions noshwordsplit

	local shell=${SHELL:-$commands[zsh]}
	print - "- Zsh: $($shell --version) ($shell)"
	print -n - "- Operating system: "
	case $(uname -s) in
		Darwin) print "$(sw_vers -productName) $(sw_vers -productVersion) ($(sw_vers -buildVersion))";;
		*) print "$(uname -s) ($(uname -r) $(uname -v) $(uname -m) $(uname -o))";;
	esac
	print - "- Terminal program: ${TERM_PROGRAM:-unknown} (${TERM_PROGRAM_VERSION:-unknown})"
	print - "- Tmux: ${${TMUX:+yes}:-no}"
	local -a git_version=($(git --version))
	print - "- Git: $git_version"
	print - "- jj: ${$(jj --version 2>/dev/null):-not installed}"
	print - "- gitstatusd: ${prompt_impure_gitstatus_inited:-not tried}"
	print - "- Impure state:"
	local k v
	for k v in "${(@kv)prompt_impure_state}"; do
		print - "    - $k: \`${(q-)v}\`"
	done
	print - "- zsh-async version: \`${ASYNC_VERSION}\`"
	print - "- PROMPT: \`$(typeset -p PROMPT)\`"
	print - "- Colors: \`$(typeset -p prompt_impure_colors)\`"
	print - "- TERM: \`$(typeset -p TERM)\`"
	print - "- Virtualenv: \`$(typeset -p VIRTUAL_ENV_DISABLE_PROMPT)\`"
}

# Render the real PROMPT and RPROMPT with every segment filled in.
prompt_impure_preview() {
	setopt localoptions noshwordsplit
	prompt_impure_set_colors

	local -a saved_psvar=("${(@)psvar}")
	psvar[12,29]=(
		${IMPURE_SUSPENDED_JOBS_SYMBOL-✦} 1 main '+2 ~1' '*' rebase-i
		"${IMPURE_GIT_UP_ARROW:-⇡}2 ${IMPURE_GIT_DOWN_ARROW:-⇣}1" '' 42s venv
		prefix suffix '[zmx]' bookmark qxzlr '~3' '' '!2'
	)
	local prompt_newline=$'\n' prompt_impure_newline=
	print -r -- "${(%)${(e)PROMPT}}    ${(%)${(e)RPROMPT}}"
	false || print -r -- "${(%)${(e)PROMPT}}    (after an error)"
	psvar=("${(@)saved_psvar}")
}

prompt_impure_setup() {
	prompt_opts=(subst percent)
	# Borrowed from `promptinit`, for when Impure is sourced directly.
	setopt noprompt{bang,cr,percent,subst} "prompt${^prompt_opts[@]}"

	# Usually set by promptinit.
	[[ -n ${prompt_newline-} ]] || typeset -g prompt_newline=$'\n%{\r%}'
	typeset -g prompt_impure_newline=
	typeset -g prompt_impure_path_sep_dim=$'%{\e[2m%}/%{\e[22m%}'

	zmodload zsh/datetime
	zmodload zsh/zle
	zmodload zsh/parameter
	zmodload zsh/zutil

	autoload -Uz add-zsh-hook
	autoload -Uz vcs_info
	autoload -Uz async
	# Zsh 5.3+.
	autoload -Uz +X add-zle-hook-widget 2>/dev/null

	typeset -gA prompt_impure_colors_default=(
		custom:prefix        242
		custom:suffix        242
		execution_time       yellow
		git:arrow            cyan
		git:branch           242
		git:action           yellow
		git:dirty            242
		jj                   242
		nix-shell            red
		path                 blue
		prompt:error         red
		prompt:success       magenta
		prompt:ssh           yellow
		prompt:continuation  242
		suspended_jobs       red
		zmx                  green
	)
	typeset -gA prompt_impure_colors=("${(@kv)prompt_impure_colors_default}")

	add-zsh-hook precmd prompt_impure_precmd
	add-zsh-hook preexec prompt_impure_preexec
	add-zsh-hook zshexit prompt_impure_zshexit

	# Ctrl+C at the prompt: zsh doesn't erase the autosuggestion drawn right of
	# the cursor, and zle can't be used here, so clear to end of screen.
	TRAPINT() {
		print -rn -- $'\e[J'
		prompt_impure_restore_prompt
		return $(( 128 + $1 ))
	}

	prompt_impure_state_setup

	zle -N prompt_impure_reset_prompt
	zle -N prompt_impure_reset_prompt_symbol
	zle -N prompt_impure_update_vim_prompt_widget
	zle -N prompt_impure_accept_line
	zle -N prompt_impure_transient_redraw
	zle -N prompt_impure_clear_screen

	# zsh-autosuggestions would otherwise repaint the suggestion after the
	# transient collapse; set here whether it loads before or after Impure.
	typeset -ga ZSH_AUTOSUGGEST_CLEAR_WIDGETS
	(( ${ZSH_AUTOSUGGEST_CLEAR_WIDGETS[(I)prompt_impure_accept_line]} )) ||
		ZSH_AUTOSUGGEST_CLEAR_WIDGETS+=(prompt_impure_accept_line)
	if (( $+functions[add-zle-hook-widget] )); then
		add-zle-hook-widget zle-line-finish prompt_impure_reset_prompt_symbol
		add-zle-hook-widget zle-keymap-select prompt_impure_update_vim_prompt_widget
		add-zle-hook-widget zle-line-finish prompt_impure_transient_redraw
	fi
	bindkey '^M' prompt_impure_accept_line
	bindkey '^J' prompt_impure_accept_line
	bindkey '^L' prompt_impure_clear_screen

	prompt_impure_clear_git_state
	prompt_impure_clear_jj_state
	prompt_impure_set_colors

	# PROMPT is built once; each %(NV.x.) segment shows only when psvar[N] is
	# set, and prompt_impure_preprompt_render keeps psvar current.
	#
	#   12 suspended jobs symbol     21 virtualenv / nix shell (RPROMPT)
	#   13 show hostname             22 custom prefix (prompt_impure_precustom)
	#   14 git branch                23 custom suffix (prompt_impure_precustom)
	#   15 git staging, "+2 ~1"      24 zmx session, "[name]"
	#   16 git dirty, "*"            25 jj bookmarks
	#   17 git action, "rebase"      26 jj change id
	#   18 git arrows, "⇡1 ⇣3"       27 jj working copy changes, "~3"
	#   20 exec time (RPROMPT)       28 git detached HEAD hash
	#                                29 conflicts, "!2"
	PROMPT='${prompt_impure_newline}'
	PROMPT+='%(13V.%F{$prompt_impure_colors[prompt:ssh]}%m%f .)'
	PROMPT+='%(24V.%F{$prompt_impure_colors[zmx]}%24v%f .)'
	PROMPT+='${(e)prompt_impure_path_segment}'
	PROMPT+='%(14V. %F{$prompt_impure_colors[git:branch]}%14v%f.)'
	PROMPT+='%(28V. %F{$prompt_impure_colors[git:branch]}%28v%f.)'
	PROMPT+='%(15V.%F{$prompt_impure_colors[git:dirty]} (%15v)%f.)'
	PROMPT+='%(16V.%F{$prompt_impure_colors[git:dirty]}%16v%f.)'
	PROMPT+='%(17V. %F{$prompt_impure_colors[git:action]}%17v%f.)'
	PROMPT+='%(18V. %F{$prompt_impure_colors[git:arrow]}%18v%f.)'
	PROMPT+='%(25V. %F{$prompt_impure_colors[jj]}%25v%f.)'
	PROMPT+='%(26V. %F{cyan}@%26v%f.)'
	PROMPT+='%(27V. %F{$prompt_impure_colors[jj]}%27v%f.)'
	PROMPT+='%(29V. %F{red}%29v%f.)'
	PROMPT+='%(22V. %F{$prompt_impure_colors[custom:prefix]}%22v%f.)'
	PROMPT+='%(23V. %F{$prompt_impure_colors[custom:suffix]}%23v%f.)'
	PROMPT+='${prompt_newline}'
	PROMPT+='%(?.%F{$prompt_impure_colors[$prompt_impure_state[prompt_color]]}.%F{$prompt_impure_colors[prompt:error]})${prompt_impure_state[prompt]}%f '
	PROMPT2='%F{$prompt_impure_colors[prompt:continuation]}${IMPURE_PROMPT_SYMBOL:-❯}%f '
	RPROMPT='%(20V.%F{$prompt_impure_colors[execution_time]}%20v%f.)'
	RPROMPT+='%(21V. %F{$prompt_impure_colors[nix-shell]}%21v%f.)'

	# PS4 for xtrace: depth as repeated +, then file:line and function:line,
	# dropping the file when it is the function itself. The %-escapes only
	# work through (%) when stored in a variable first.
	typeset -ga prompt_impure_debug_depth=('%e' '%N' '%x')
	local -A ps4_parts=(
		depth     '%F{yellow}${(l:${(%)prompt_impure_debug_depth[1]}::+:)}%f'
		compare   '${${(%)prompt_impure_debug_depth[2]}:#${(%)prompt_impure_debug_depth[3]}}'
		main      '%F{blue}${${(%)prompt_impure_debug_depth[3]}:t}%f%F{242}:%I%f %F{242}@%f%F{blue}%N%f%F{242}:%i%f'
		secondary '%F{blue}%N%f%F{242}:%i'
		prompt    '%F{242}>%f '
	)
	local ps4_symbols='${${'${ps4_parts[compare]}':+"'${ps4_parts[main]}'"}:-"'${ps4_parts[secondary]}'"}'
	PROMPT4="${ps4_parts[depth]} ${ps4_symbols}${ps4_parts[prompt]}"

	# Keep Oh My Zsh themes and pyenv-virtualenv off PROMPT.
	unset ZSH_THEME
	export PYENV_VIRTUALENV_DISABLE_PROMPT=1
}

prompt_impure_setup "$@"
