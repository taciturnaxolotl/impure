#!/usr/bin/env zsh
# Test harness for impure prompt — automated edge case testing.
# Usage: zsh tests/test-prompt.zsh [test-name]
#   test-name: transient | fingerprint | jj | all (default: all)

setopt NO_GLOBAL_RCS NO_RCS

TESTS_DIR="${0:A:h}"
IMPURE_DIR="${TESTS_DIR:A:h}"

source "$IMPURE_DIR/async.zsh"
source "$IMPURE_DIR/impure.zsh"

PASS=0
FAIL=0

assert_eq() {
    local desc=$1 expected=$2 actual=$3
    if [[ "$expected" == "$actual" ]]; then
        print -P "%F{green}✓%f $desc"
        (( PASS++ ))
    else
        print -P "%F{red}✗%f $desc"
        print -P "  expected: ${(qq)expected}"
        print -P "  actual:   ${(qq)actual}"
        (( FAIL++ ))
    fi
}

assert_not_empty() {
    local desc=$1 value=$2
    if [[ -n "$value" ]]; then
        print -P "%F{green}✓%f $desc"
        (( PASS++ ))
    else
        print -P "%F{red}✗%f $desc (empty)"
        (( FAIL++ ))
    fi
}

assert_empty() {
    local desc=$1 value=$2
    if [[ -z "$value" ]]; then
        print -P "%F{green}✓%f $desc"
        (( PASS++ ))
    else
        print -P "%F{red}✗%f $desc (got: ${(qq)value})"
        (( FAIL++ ))
    fi
}

# --- Tests ---

test_colors_initialized() {
    print "\n--- Colors ---"
    assert_not_empty "prompt:success color set" "$prompt_impure_colors[prompt:success]"
    assert_not_empty "prompt:error color set" "$prompt_impure_colors[prompt:error]"
    assert_not_empty "prompt:ssh color set" "$prompt_impure_colors[prompt:ssh]"
    assert_not_empty "path color set" "$prompt_impure_colors[path]"
    assert_not_empty "path:ephemeral color set" "$prompt_impure_colors[path:ephemeral]"
    assert_not_empty "jj color set" "$prompt_impure_colors[jj]"
    assert_not_empty "zmx color set" "$prompt_impure_colors[zmx]"
    assert_not_empty "nix-shell color set" "$prompt_impure_colors[nix-shell]"
}

test_prompt_contains_symbol() {
    print "\n--- Prompt structure ---"
    # PROMPT should contain the prompt symbol reference
    if [[ "$PROMPT" == *'prompt_impure_state[prompt]'* ]]; then
        print -P "%F{green}✓%f PROMPT contains symbol reference"
        (( PASS++ ))
    else
        print -P "%F{red}✗%f PROMPT missing symbol reference"
        (( FAIL++ ))
    fi

    # PROMPT should NOT contain prompt_newline before the symbol (single info line)
    # but SHOULD contain it somewhere (two-line layout: info + chevron)
    if [[ "$PROMPT" == *'prompt_newline'* ]]; then
        print -P "%F{green}✓%f PROMPT has newline (two-line layout)"
        (( PASS++ ))
    else
        print -P "%F{red}✗%f PROMPT missing newline"
        (( FAIL++ ))
    fi
}

test_rprompt_built() {
    print "\n--- RPROMPT ---"
    assert_not_empty "RPROMPT is set" "$RPROMPT"
    # RPROMPT should contain exec time conditional
    if [[ "$RPROMPT" == *'20V'* ]]; then
        print -P "%F{green}✓%f RPROMPT contains exec time"
        (( PASS++ ))
    else
        print -P "%F{red}✗%f RPROMPT missing exec time"
        (( FAIL++ ))
    fi
}

test_fingerprint_stable() {
    print "\n--- Fingerprint stability ---"
    # Simulate two consecutive precmd renders with no state change
    prompt_impure_preprompt_render "precmd"
    local fp1="$prompt_impure_last_prompt"

    prompt_impure_preprompt_render
    local fp2="$prompt_impure_last_prompt"

    assert_eq "fingerprint stable across renders" "$fp1" "$fp2"

    # Exec time should NOT be in fingerprint
    # Set exec time, check fingerprint doesn't change
    typeset -g prompt_impure_cmd_exec_time="5s"
    psvar[20]="5s"
    psvar[21]=  # clear nix-shell to avoid interference
    prompt_impure_preprompt_render
    local fp3="$prompt_impure_last_prompt"

    assert_eq "exec time excluded from fingerprint" "$fp1" "$fp3"

    unset prompt_impure_cmd_exec_time
    psvar[19]=
}

test_transient_flag() {
    print "\n--- Transient prompt ---"
    # accept-line wrapper should exist
    if (( $+widgets[prompt_impure_accept_line] )); then
        print -P "%F{green}✓%f accept-line widget registered"
        (( PASS++ ))
    else
        print -P "%F{red}✗%f accept-line widget not registered"
        (( FAIL++ ))
    fi

    # transient redraw widget should exist
    if (( $+widgets[prompt_impure_transient_redraw] )); then
        print -P "%F{green}✓%f transient redraw widget registered"
        (( PASS++ ))
    else
        print -P "%F{red}✗%f transient redraw widget not registered"
        (( FAIL++ ))
    fi

    # Simulate transient cycle
    typeset -g prompt_impure_transient=1
    local saved_prompt="$PROMPT"
    local saved_rprompt="$RPROMPT"

    # Manually call the redraw (outside zle context, so skip zle calls)
    prompt_impure_transient_redraw 2>/dev/null

    assert_eq "PROMPT swapped to minimal" "%F{${prompt_impure_colors[prompt:success]}}❯%f " "$PROMPT"
    assert_empty "RPROMPT cleared during transient" "$RPROMPT"
    assert_not_empty "saved prompt stored" "$prompt_impure_saved_prompt"

    # Restore via precmd path
    PROMPT=$prompt_impure_saved_prompt
    RPROMPT=$prompt_impure_saved_rprompt
    unset prompt_impure_saved_prompt prompt_impure_saved_rprompt
    prompt_impure_build_rprompt

    assert_eq "PROMPT restored after transient" "$saved_prompt" "$PROMPT"
}

test_zmx_segment() {
    print "\n--- ZMX session ---"
    ZMX_SESSION="test-session"
    prompt_impure_preprompt_render "precmd"
    assert_eq "ZMX psvar set" "[test-session]" "${psvar[24]}"
    unset ZMX_SESSION
    prompt_impure_preprompt_render "precmd"
    assert_empty "ZMX psvar cleared" "${psvar[24]}"
}

test_ephemeral_path() {
    print "\n--- Ephemeral path ---"
    ATELIER_EPHEMERAL=1
    prompt_impure_set_path_separator
    if [[ "$prompt_impure_path_segment" == *"${prompt_impure_colors[path:ephemeral]}"* ]]; then
        print -P "%F{green}✓%f ephemeral uses red path color"
        (( PASS++ ))
    else
        print -P "%F{red}✗%f ephemeral not using red path color"
        (( FAIL++ ))
    fi
    unset ATELIER_EPHEMERAL
    prompt_impure_set_path_separator
    if [[ "$prompt_impure_path_segment" == *"${prompt_impure_colors[path]}"* ]]; then
        print -P "%F{green}✓%f normal uses blue path color"
        (( PASS++ ))
    else
        print -P "%F{red}✗%f normal not using blue path color"
        (( FAIL++ ))
    fi
}

test_jj_async_function() {
    print "\n--- Jujutsu async ---"
    # The async function should exist
    if (( $+functions[prompt_impure_async_jj_status] )); then
        print -P "%F{green}✓%f jj async status function exists"
        (( PASS++ ))
    else
        print -P "%F{red}✗%f jj async status function missing"
        (( FAIL++ ))
    fi

    # Outside a jj repo, should return 1
    (cd /tmp && prompt_impure_async_jj_status) 2>/dev/null
    local ret=$?
    assert_eq "jj status returns 1 outside jj repo" "1" "$ret"
}

test_ssh_prompt_color() {
    print "\n--- SSH prompt color ---"
    # Without SSH, prompt indicator should use prompt:success
    if [[ "$PROMPT" == *'prompt:ssh'* ]] && [[ "$PROMPT" == *'13V'*'prompt:ssh'* ]]; then
        print -P "%F{green}✓%f PROMPT has SSH-conditional color"
        (( PASS++ ))
    else
        print -P "%F{red}✗%f PROMPT missing SSH-conditional color"
        (( FAIL++ ))
    fi
}

# --- Runner ---

run_test() {
    case $1 in
        colors)      test_colors_initialized ;;
        structure)   test_prompt_contains_symbol ;;
        rprompt)     test_rprompt_built ;;
        fingerprint) test_fingerprint_stable ;;
        transient)   test_transient_flag ;;
        zmx)         test_zmx_segment ;;
        ephemeral)   test_ephemeral_path ;;
        jj)          test_jj_async_function ;;
        ssh)         test_ssh_prompt_color ;;
        all)
            test_colors_initialized
            test_prompt_contains_symbol
            test_rprompt_built
            test_fingerprint_stable
            test_transient_flag
            test_zmx_segment
            test_ephemeral_path
            test_jj_async_function
            test_ssh_prompt_color
            ;;
        *)
            print "Unknown test: $1"
            print "Available: colors structure rprompt fingerprint transient zmx ephemeral jj ssh all"
            exit 1
            ;;
    esac
}

target=${1:-all}
run_test "$target"

print "\n--- Results ---"
print -P "%F{green}${PASS} passed%f, %F{red}${FAIL} failed%f"
(( FAIL > 0 )) && exit 1
exit 0
