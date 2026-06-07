# impure

> A pretty, minimal and fast ZSH prompt — a fork of [Pure](https://github.com/sindresorhus/pure) with Jujutsu, nix-shell, and zmx awareness

The canonical repo for this is hosted on tangled over at [`dunkirk.sh/impure`](https://tangled.org/dunkirk.sh/impure)

<img src="screenshot.png" width="864">

## Features

- **Async git status.** Branch, dirty marker, and unpushed/unpulled arrows are
  computed in a background worker so the prompt never blocks.
- **Staging summary.** Dirty repos show an oh-my-posh-style breakdown of the
  index, e.g. `main (+2 ~1 -1)*` — added, modified, deleted, plus a `*` when the
  working tree is dirty.
- **Jujutsu support.** Inside a `jj` repo the prompt shows bookmarks, the short
  change ID (in cyan), and a working-copy change count. `jj` takes precedence
  over git when both are present.
- **nix-shell and virtualenv.** The active environment name is shown on the
  right prompt.
- **zmx sessions.** When `$ZMX_SESSION` is set the tag is shown in the preprompt.
- **Transient prompt.** After you press Enter the two-line prompt collapses to a
  single `❯` in scrollback, keeping history clean.
- **Custom segments.** Define `prompt_impure_precustom` to inject your own prefix
  and suffix segments.
- **Exec time, SSH/container detection, VI-mode indicator, suspended-jobs
  marker** — all carried over from Pure.

Requires Git 2.15.2+ and ZSH 5.2+ (5.3+ recommended for VI-mode and transient
prompt). `jujutsu` is optional and only needed for jj status.

## Install

### Arch Linux

A `PKGBUILD` is provided under [`arch/`](arch/PKGBUILD). Build and install it
with `makepkg -si`.

### Manually

1. Clone this repo somewhere, e.g. `$HOME/.zsh/impure`:

   ```sh
   mkdir -p "$HOME/.zsh"
   git clone https://tangled.org/dunkirk.sh/impure "$HOME/.zsh/impure"
   ```

2. Add the path to `fpath` in `$HOME/.zshrc`:

   ```sh
   fpath+=("$HOME/.zsh/impure")
   ```

## Getting started

Initialize the prompt system (if not already) and choose `impure`:

```sh
# .zshrc
autoload -U promptinit; promptinit
prompt impure
```

## Configuration

### Environment variables

| Variable                       | Default | Description                                                   |
| ------------------------------ | ------- | ------------------------------------------------------------- |
| `IMPURE_CMD_MAX_EXEC_TIME`     | `3`     | Seconds before a command's exec time is shown.                |
| `IMPURE_GIT_PULL`              | `1`     | Set to `0` to disable the background `git fetch`.             |
| `IMPURE_GIT_UNTRACKED_DIRTY`   | `1`     | Set to `0` to ignore untracked files when checking dirtiness. |
| `IMPURE_GIT_DELAY_DIRTY_CHECK` | `1800`  | Seconds to cache a slow dirty check before re-running.        |
| `IMPURE_PROMPT_SYMBOL`         | `❯`     | The prompt symbol.                                            |
| `IMPURE_PROMPT_VICMD_SYMBOL`   | `❮`     | The prompt symbol in VI command mode.                         |
| `IMPURE_GIT_UP_ARROW`          | `⇡`     | Symbol for unpushed commits.                                  |
| `IMPURE_GIT_DOWN_ARROW`        | `⇣`     | Symbol for unpulled commits.                                  |
| `IMPURE_GIT_STASH_SYMBOL`      | `≡`     | Symbol shown when stashes exist.                              |
| `IMPURE_SUSPENDED_JOBS_SYMBOL` | `✦`     | Symbol shown when jobs are suspended.                         |

The prompt also reacts to these external variables when set:

- `ZMX_SESSION` — renders a `[session]` tag in the preprompt.

### zstyles

All toggles default to **on** unless noted. Disable a feature by setting its
style to `no` before `prompt impure`:

```sh
zstyle ':prompt:impure:git'                 show no   # disable git integration
zstyle ':prompt:impure:jj'                  show no   # disable jujutsu integration
zstyle ':prompt:impure:host'                show no   # hide hostname
zstyle ':prompt:impure:title'               show no   # stop managing the terminal title
zstyle ':prompt:impure:git:stash'           show yes  # show stash indicator
zstyle ':prompt:impure:git:fetch'   only_upstream yes # only fetch the current branch's upstream
zstyle ':prompt:impure:environment:nix-shell'  show no
zstyle ':prompt:impure:environment:virtualenv' show no
zstyle ':prompt:impure:path:separator'      dim  yes  # dim the path separators
```

### Colors

Override any segment color with the `color` style. Values are zsh color names or
256-color numbers:

```sh
zstyle ':prompt:impure:path' color blue
zstyle ':prompt:impure:git:branch' color 242
zstyle ':prompt:impure:prompt:success' color magenta
```

Available color keys: `path`, `git:branch`,
`git:branch:cached`, `git:dirty`, `git:action`, `git:arrow`, `git:stash`, `jj`,
`host`, `user`, `user:root`, `zmx`, `nix-shell`, `virtualenv`,
`execution_time`, `suspended_jobs`, `custom:prefix`, `custom:suffix`,
`prompt:success`, `prompt:error`, `prompt:ssh`, `prompt:continuation`.

### Custom segments

Define `prompt_impure_precustom` to add your own prefix/suffix segments. It runs
on every render and can set `psvar[22]` (prefix) and `psvar[23]` (suffix):

```sh
prompt_impure_precustom() {
	psvar[22]="$(date +%H:%M)"   # rendered before the path
	psvar[23]=""                 # rendered after the git/jj segments
}
```

## Preview

Run `prompt_impure_preview` after loading the prompt to see every segment and
color rendered at once.

## Tests

```sh
zsh tests/test.zsh
```

Each test file runs in its own subshell; the harness exits non-zero if any fail.

## Credits

Impure is a fork of [Pure](https://github.com/sindresorhus/pure) by Sindre
Sorhus and Mathias Fredriksson, and bundles
[`zsh-async`](https://github.com/mafredri/zsh-async). All of the hard work on the
async core and the original prompt design is theirs; Impure adds the jj, nix,
zmx and staging-summary layers on top.

<p align="center">
    <img src="https://raw.githubusercontent.com/taciturnaxolotl/carriage/main/.github/images/line-break.svg" />
</p>

<p align="center">
    <i><code>&copy; 2026-present <a href="https://dunkirk.sh">Kieran Klukas</a></code></i>
</p>

<p align="center">
    <a href="https://tangled.org/dunkirk.sh/impure/blob/main/LICENSE.md"><img src="https://img.shields.io/static/v1.svg?style=for-the-badge&label=License&message=MIT&logoColor=d9e0ee&colorA=363a4f&colorB=b7bdf8"/></a>
</p>
