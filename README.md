# shrc

**A compact, cross-platform shell toolbox for Unix and PowerShell.**

`shrc` puts everyday shortcuts, command wrappers, self-updates, and optional
host utilities behind one small command surface. Source one profile file, then
install larger scripts only when you need them.

```text
src              reload the profile
urc -a           update the profile and installed tool catalog
ish <tool>       install or update one tool
rsh <tool> ...   run an installed tool
```

## Why use it?

- **One workflow on two platforms** — `src`, `urc`, `ish`, and `rsh` work in
  Bash/Zsh and PowerShell.
- **Useful commands immediately** — inspect processes, scope a proxy to one
  command, check listening ports, manage Conda/Docker, and search
  files with short, memorable commands.
- **Host-facing tools stay optional** — service management, `tscp`, SSH
  forwarding, tunneled RDP, and Windows device cleanup live in independently
  installed scripts.
- **Easy to audit** — the complete system is one sourced profile plus one flat
  script directory; there is no nested plugin framework.
- **Safer updates** — downloads use temporary files, and main profiles are
  loaded or parsed before replacing the active copy.

## Quick start

### Unix: Bash or Zsh

```sh
curl -fsSL -- https://gitee.com/kurayuri/shrc/raw/main/.shrc \
  -o "$HOME/.shrc"
. "$HOME/.shrc"
```

Make it persistent by adding this line to `~/.bashrc` or `~/.zshrc`:

```sh
[ -f "$HOME/.shrc" ] && . "$HOME/.shrc"
```

Install every optional Unix tool, or only the one you want:

```sh
ish -a
# or
ish tscp
```

Requirements: Bash or Zsh and `curl`.

### Windows: PowerShell

```powershell
$ShProfileUrl = "https://gitee.com/kurayuri/shrc/raw/main/.shprofile.ps1"
Invoke-WebRequest -UseBasicParsing -Uri $ShProfileUrl -OutFile (Join-Path $HOME ".shprofile.ps1")
. (Join-Path $HOME ".shprofile.ps1")
```

Make it persistent by adding this line to each PowerShell `$PROFILE` that
should load the toolbox:

```powershell
. (Join-Path $HOME ".shprofile.ps1")
```

Windows PowerShell 5.1 and PowerShell 7 can therefore share the same
`$HOME\.shprofile.ps1` even though they use different `$PROFILE` files.

Install all optional PowerShell tools, or only tunneled RDP:

```powershell
ish -a
# or
ish Connect-TunnelRdp
```

## Recipes

### Find the process or port you care about

```sh
pxil python        # current user's active Python processes
nsl 8080           # listening sockets containing 8080
fx . TODO          # recursively find the word TODO
ffa . checkpoint   # case-insensitive filename search
```

### Use a proxy without changing the parent shell

```sh
proxy http://127.0.0.1:7890 -- curl https://example.com
```

Or enable it in the current shell and remove it later:

```sh
proxy http://127.0.0.1:7890
unproxy
```

### Transfer a directory through SSH

```sh
ish tscp

tscp ./dataset work /srv/data          # local -> remote
tscp -rz work /srv/results ./results   # remote -> local, compressed
```

`tscp` streams a tar archive over the existing OpenSSH configuration. It
retries the specific “file changed as we read it” case up to five times; add
`-1` to attempt only once.

### Open an SSH tunnel or tunneled RDP session

```powershell
ish Connect-SshLocalPortForward
sshl work 8080 80

ish Connect-TunnelRdp
trdp work
```

`sshl` forwards a local port to `localhost` on the SSH host. `trdp` assigns a
stable loopback address per SSH host, opens the tunnel, waits for it to become
ready, and launches the built-in Windows RDP client. See the
[PowerShell tools guide](.shprofile_scripts/README.md) for host configuration,
concurrent sessions, and Windows Credential Manager integration.

## Built-in Unix toolbox

These commands are available as soon as `.shrc` is sourced:

| Command | What it does | Example |
| --- | --- | --- |
| `px` | Filter processes by state, user, command, or full arguments. | `px -ui la python` |
| `proxy` / `unproxy` | Set proxy variables globally or for one command. | `proxy -- curl example.com` |
| `ns` | Filter TCP/UDP and listening sockets from `netstat`. | `ns -tl 8080` |
| `ff` / `ffa` | Find exact or fuzzy filenames. | `ff . '*.log'` |
| `fx` / `fxa` | Search exact words or arbitrary text recursively. | `fxa src FIXME` |
| `dk` | Short Docker subcommands for images, containers, exec, and contexts. | `dk xb dev` |
| `cn` | Create, activate, list, and remove Conda environments. | `cn nn research` |
| `tx` | Attach to tmux sessions or capture pane history. | `tx at research` |
| `sudox` | Run a command through `sudo` with `.shrc` loaded. | `sudox svc p sshd` |

Most wrappers pass unrecognized arguments to the underlying command, so the
original CLI remains available. For example, `dk compose up` runs
`docker compose up`.

## Optional tools

### Unix

| Tool | Purpose |
| --- | --- |
| `init` | Bootstrap packages, Conda, SSH, and shell settings on a Unix host. |
| `file_configs` | Write the repository's tmux and pip configuration defaults. |
| `init_project` | Create common project files such as `.gitignore`. |
| `svc` | Auto-select the system or user manager for service actions and inspect journals. |
| `tscp` | Push or pull directory trees through SSH using tar streams. |

### PowerShell

| Tool | Shortcut | Purpose |
| --- | --- | --- |
| `Connect-SshLocalPortForward` | `sshl` | Create an OpenSSH local port forward. |
| `Connect-TunnelRdp` | `trdp` | Start Windows RDP through an OpenSSH tunnel. |
| `Remove-Ghosts` | — | List or remove non-present Windows devices. |

Install tools by name without their `.sh` or `.ps1` extension:

```text
ish <name>       install or update one tool
ish -a           install or update every manifest tool
rsh <name> ...   run one installed tool
```

The dedicated `svc`, `tscp`, `sshl`, and `trdp` wrappers call the same installed
scripts, so normal usage stays short.

For `svc av`, `dv`, `sa`, `sp`, `rs`, `rl`, and `p`, put the service name
immediately after the action. `svc` checks the installed system and user unit
files automatically. A user-only service is sent to `systemctl --user`; a
system-only service is sent to the system manager. If both scopes contain the
name, the system manager wins and `svc` prints a notice. If neither contains
the name, no action is run.

## Profile manager

| Command | Purpose |
| --- | --- |
| `src` | Reload the current profile. |
| `urc` | Download and activate the latest main profile. |
| `urc -a` | Update the profile and every manifest tool. |
| `ish <name>` | Install or update one optional tool. |
| `ish -a` | Install or update every tool in the platform manifest. |
| `rsh <name> [args...]` | Run an installed tool with the supplied arguments. |

Unix also exposes the long-form interface:

```text
shrc source
shrc update [-a]
shrc install <name>|-a
shrc run <name> [args...]
shrc edit
shrc view
shrc clear
```

## Two-layer layout

```text
Unix                              PowerShell
$HOME/.shrc                       $HOME/.shprofile.ps1
        |                                  |
        v                                  v
$HOME/.shrc_scripts/              $HOME/.shprofile_scripts/
```

The profile is the always-loaded control plane: aliases, interactive helpers,
and the script manager. The sibling directory is the on-demand tool plane:
larger commands that can be downloaded, reviewed, updated, and run
independently.

Repository paths intentionally match their final paths under `$HOME`:

```text
.
├── .shrc
├── .shrc_scripts/
│   ├── manifest.txt
│   └── *.sh
├── .shprofile.ps1
├── .shprofile_scripts/
│   ├── manifest.txt
│   └── *.ps1
└── tests/
    ├── test_svc.sh
    └── Connect-TunnelRdp.Tests.ps1
```

## Safety

- Review host-management scripts before running them on a new machine.
- `init` installs packages and changes host configuration.
- `file_configs` writes tmux and pip configuration files.
- `Remove-Ghosts` can remove Windows devices. Start with the read-only command
  `rsh Remove-Ghosts -listGhostDevicesOnly`; removal may require elevation and
  has no built-in undo.
- `urc` and `ish` download from this repository's `main` branch.

## Testing

Run the Unix service-scope test suite with Bash:

```sh
bash tests/test_svc.sh
```

Run the tunneled RDP test suite from the repository root:

```powershell
Invoke-Pester .\tests\Connect-TunnelRdp.Tests.ps1
```

The tests support Pester 3.4 as included with Windows PowerShell.
