# Impure Instant Prompt — print minimal prompt before shell init completes.
# Source this early in .zshrc, before compinit/plugins/heavy init.
# Generates directory + symbol dynamically (~1ms). No cache needed.

[[ -o interactive && -o zle ]] || return
[[ -t 0 && -t 1 && -t 2 ]] || return

() {
	# Build minimal prompt: path + newline + prompt symbol.
	# Use %~ to match impure's prompt (shortens $HOME to ~).
	local dir="${(%):-%~}"
	# Hardcoded colors matching impure defaults (theme vars not loaded yet).
	# blue=4 for path, magenta=5 for prompt symbol, 242 for ssh host.
	local c_blue=$'\e[34m' c_magenta=$'\e[35m' c_yellow=$'\e[33m' c_gray=$'\e[38;5;242m' c_reset=$'\e[0m'
	local ssh=
	local prompt_color=$c_magenta
	if [[ -n "$SSH_CLIENT$SSH_TTY$SSH_CONNECTION" ]]; then
		ssh="${c_gray}${(%):-%m}${c_reset} "
		prompt_color=$c_yellow
	fi
	local minimal="${c_blue}${dir}${c_reset}"$'\n'"${prompt_color}❯${c_reset} "

	# Print with terminal reset + cursor save (p10k-compatible format).
	zmodload zsh/terminfo 2>/dev/null
	if (( $+terminfo[sc] )); then
		print -rn -- "${(%):-%b%k%f%s%u}${terminfo[sc]}${minimal}"
	else
		print -rn -- "${(%):-%b%k%f%s%u}${minimal}"
	fi

	# Set PROMPT so ZLE's first render matches (no flicker).
	PROMPT="$minimal"
	RPROMPT=''

	# Signal that instant prompt is active for cleanup on first precmd.
	typeset -g IMPURE_INSTANT_PROMPT_ACTIVE=1

	# Redirect stdout/stderr during init to prevent output smearing over the prompt.
	# Stdin goes to /dev/null so nothing reads from the terminal during init.
	# Uses sysopen (like p10k) for robust fd management.
	zmodload zsh/system 2>/dev/null || return
	typeset -g IMPURE_IP_OUTPUT_FILE="${TMPDIR:-/tmp}/impure-ip-output-$$"
	{ : > "$IMPURE_IP_OUTPUT_FILE" } 2>/dev/null || return
	local fd_null
	sysopen -ru fd_null /dev/null 2>/dev/null || return
	# Save the terminal on close-on-exec fds. `exec {fd}>&N` dups are NOT
	# close-on-exec, so any program spawned during init (e.g. a daemon started
	# from .zshrc, like a syntax-highlighter or prompt helper) inherits these
	# tty fds and pins the terminal open. A held-open PTY slave never signals
	# EOF, which wedges terminal multiplexers (tmux, zmx) when the shell exits.
	# Reopening $TTY with -o cloexec makes the saved fds auto-close on exec
	# while staying valid inside this shell for the restore in precmd cleanup.
	if ! sysopen -o cloexec -rw -u IMPURE_IP_FD_0 $TTY 2>/dev/null \
		|| ! sysopen -o cloexec -rw -u IMPURE_IP_FD_1 $TTY 2>/dev/null \
		|| ! sysopen -o cloexec -rw -u IMPURE_IP_FD_2 $TTY 2>/dev/null; then
		return
	fi
	exec 0<&$fd_null 1>"$IMPURE_IP_OUTPUT_FILE"
	exec 2>&1 {fd_null}>&-
}
