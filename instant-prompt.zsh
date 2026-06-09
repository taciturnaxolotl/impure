# Impure Instant Prompt — print minimal prompt before shell init completes.
# Source this early in .zshrc, before compinit/plugins/heavy init.
# Generates directory + symbol dynamically (~1ms). No cache needed.

[[ -o interactive && -o zle ]] || return
[[ -t 0 && -t 1 && -t 2 ]] || return

() {
	# Build minimal prompt: path + newline + prompt symbol.
	# Use %~ to match impure's prompt (shortens $HOME to ~).
	local dir="${(%):-%~}"
	local ssh=
	[[ -n "$SSH_CLIENT$SSH_TTY$SSH_CONNECTION" ]] && ssh="${(%):-%m} "
	local minimal="${ssh}${dir}"$'\n'"❯ "

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
	exec {IMPURE_IP_FD_0}<&0 {IMPURE_IP_FD_1}>&1 {IMPURE_IP_FD_2}>&2 \
		0<&$fd_null 1>"$IMPURE_IP_OUTPUT_FILE"
	exec 2>&1 {fd_null}>&-
}
