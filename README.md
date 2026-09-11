# `tree-sitter-git-config`

[![CI](https://github.com/the-mikedavis/tree-sitter-git-config/actions/workflows/ci.yml/badge.svg)](https://github.com/the-mikedavis/tree-sitter-git-config/actions/workflows/ci.yml)

A [tree-sitter](https://tree-sitter.github.io/tree-sitter/) grammar for git's configuration language

NOTE: when contributing, you can skip checking in the changes from `tree-sitter generate`. CI will push a commit to regenerate the parser on merge.

## Fork divergence

This fork adds a `hotkey` node inside comments for `[k]ey`-style annotations (e.g. `# [p]retty [l]og`, `[a]lia[s]`, `pre[t]ty`, `[f]in[d]`), so an editor query can exempt only those fragments from spell checking while the rest of the comment prose stays spellable. A whole-word bracket with no inner bracket (`[alias]`, `[find]`) is **not** a `hotkey`. See the consuming query at `~/.config/nvim/after/queries/git_config/highlights.scm` (`(hotkey) @nospell`).

## Building & installing

The `Makefile` provides convenience targets for building the parser and installing it where Neovim and the `tree-sitter` CLI expect it.
They wrap `tree-sitter generate` / `tree-sitter build`, so after editing `grammar.js` the generated sources (`src/parser.c`, …) are refreshed automatically.

| TARGET              | WHAT IT DOES                                                                                                                                      | OUTPUT                                                               |
|---------------------|---------------------------------------------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------|
| `make nvim`         | Build the parser Neovim loads. On macOS it also re-signs it (see note below).                                                                     | `./git_config.so`                                                    |
| `make nvim-install` | `make nvim` **plus** install into Neovim's runtime parser dir, **plus** refresh the CLI cache (`cli-install`). This is the one to run day-to-day. | `~/.local/share/nvim/site/parser/git_config.so` + CLI cache          |
| `make cli-install`  | Build the parser into the `tree-sitter` CLI cache so `tree-sitter parse` / `highlight` outside this repo use the latest grammar.                  | `~/.cache/tree-sitter/lib/git_config.dylib` (Linux: `git_config.so`) |

```sh
# after changing grammar.js, rebuild & install everywhere:
$ make nvim-install
tree-sitter build -o git_config.so
codesign --force --sign - git_config.so
install -d '~/.cache/tree-sitter/lib'
tree-sitter build -o '~/.cache/tree-sitter/lib/git_config.dylib'
codesign --force --sign - '~/.cache/tree-sitter/lib/git_config.dylib'
install -d '~/.local/share/nvim/site/parser'
install -m755 git_config.so '~/.local/share/nvim/site/parser/git_config.so'
codesign --force --sign - '~/.local/share/nvim/site/parser/git_config.so'
```

### nvim nvim-treesitter plugin integration

```vim
" .vimrc
Plug 'nvim-treesitter/nvim-treesitter', { 'branch': 'main', 'do': ':TSUpdate' }
```

```lua
-- init.lua
pcall(function()
  require('nvim-treesitter.parsers').git_config = {
    install_info = {
      path    = '/opt/ts/tree-sitter-git-config.git',
      queries = 'queries',
    },
  }
end)
```

- `:TSUpdateAll` — updates all parsers and re-builds + re-signs the local `groovy.so` / `git_config.so` and installs them to Neovim's parser dir.
- `:TSUpdateGitConfig` — rebuilds the local `git_config.so` and installs it to Neovim's parser dir, without updating other parsers.

Overridable variables:

- `NVIM_PARSER_DIR` — Neovim parser directory (default `~/.local/share/nvim/site/parser`)
- `TS_CACHE_DIR` — tree-sitter CLI cache dir (default `~/.cache/tree-sitter/lib`)
- `TS` — the tree-sitter CLI to use (default `tree-sitter`)

```sh
make nvim-install NVIM_PARSER_DIR=/some/other/parser
```

### Why three different artifacts?

The same grammar is consumed by three independent parsers; updating one does
**not** update the others:

| CONSUMER                                     | FILE IT LOADS                                   | REFRESHED BY                                     |
|----------------------------------------------|-------------------------------------------------|--------------------------------------------------|
| Neovim (`:InspectTree`, highlighting)        | `~/.local/share/nvim/site/parser/git_config.so` | `make nvim-install`                              |
| `tree-sitter` CLI (run outside the repo)     | `~/.cache/tree-sitter/lib/git_config.dylib`     | `make cli-install` (auto-rebuilt by the CLI too) |
| `tree-sitter test` / parsing inside the repo | `src/parser.c`                                  | `tree-sitter generate`                           |

> [!TIP]
> On macOS, `.so` and `.dylib` are the **same** Mach-O format — only the file
> name differs. Neovim always uses the `.so` name on every platform, while the
> CLI uses the OS-native extension (`.dylib` on macOS, `.so` on Linux).

### macOS code signing

`tree-sitter build` emits a *linker-signed* ad-hoc signature that macOS refuses to `dlopen` — Neovim crashes on startup with `SIGKILL` / "Code Signature Invalid".
The `nvim` / `nvim-install` targets therefore re-sign the parser with `codesign --force --sign -` on macOS.
If you build the parser by hand, re-sign it yourself:

```sh
codesign --force --sign - ~/.local/share/nvim/site/parser/git_config.so
codesign --force --sign - ~/.cache/tree-sitter/lib/git_config.dylib
```
