# Impure Instant Prompt — print minimal prompt before shell init completes.
# Source this early in .zshrc, before compinit/plugins/heavy init.
# Generates directory + symbol dynamically (~1ms). No cache needed.

[[ -o interactive && -o zle ]] || return
[[ -t 0 && -t 1 && -t 2 ]] || return

# Build minimal prompt: path + newline + prompt symbol.
local _ip_dir="$PWD"
local _ip_ssh=
[[ -n "$SSH_CLIENT$SSH_TTY$SSH_CONNECTION" ]] && _ip_ssh="${(%):-%m} "
local _ip_minimal="${_ip_ssh}${_ip_dir}"$'\n'"❯ "

# Print with terminal reset + cursor save + bracketed paste (p10k-compatible format).
zmodload zsh/terminfo 2>/dev/null
print -rn -- "${(%):-%b%k%f%s%u}${terminfo[sc]}${_ip_minimal}"$'\e[?2004h'

# Set PROMPT so ZLE's first render matches (no flicker).
PROMPT="$_ip_minimal"
RPROMPT=''

# Signal that instant prompt is active for cleanup on first precmd.
typeset -g IMPURE_INSTANT_PROMPT_ACTIVE=1

unset _ip_dir _ip_ssh _ip_minimal
