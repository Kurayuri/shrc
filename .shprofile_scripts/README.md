# .shprofile_scripts

## Installation

The standard PowerShell `$PROFILE` only needs to load the main configuration
from `$HOME\.shprofile.ps1`. Windows PowerShell 5.1 and PowerShell 7 may use
different `$PROFILE` files while sharing the same `.shprofile.ps1`.

Download the main configuration:

```powershell
$ShProfileUrl = "https://gitee.com/kurayuri/shrc/raw/main/.shprofile.ps1"
Invoke-WebRequest -UseBasicParsing -Uri $ShProfileUrl -OutFile (Join-Path $HOME ".shprofile.ps1")
```

Create `$PROFILE` if necessary, then add this block to it:

```powershell
. (Join-Path $HOME ".shprofile.ps1")
```

Or run this command to append it automatically:
```powershell
Add-Content -Path $PROFILE.CurrentUserAllHosts -Value '. (Join-Path $HOME ".shprofile.ps1")'
```

Load the configuration and install every child script:

```powershell
. $PROFILE
ish -a
```

## Connect-TunnelRdp (`trdp`)

`trdp` creates an RDP tunnel using the existing OpenSSH configuration and then
starts the built-in Windows `mstsc` client. It supports Windows PowerShell 5.1
and requires no additional modules.

### Usage

Install and run it through the `.shprofile_scripts` manager:

```powershell
ish Connect-TunnelRdp
trdp work
```

The canonical script can also be run directly:

```powershell
.\Connect-TunnelRdp.ps1 work
```

When an SSH host is used for the first time, `trdp` assigns it a stable, unique
`127.0.A.B` address and immediately writes the assignment to
`~/.config/trdp-config.json`. Later invocations reuse the same address. Host
matching is case-insensitive.

Every tunnel uses the fixed local port `33389`:

```text
work -> 127.0.42.17:33389
lab  -> 127.0.93.66:33389
```

Different hosts receive different loopback addresses, so they can use the same
port concurrently. If the same host is started twice, the second invocation
reports that the endpoint is already in use.

SSH arguments are passed to `ssh.exe`. Continue to manage `HostName`, `User`,
`Port`, `IdentityFile`, `ProxyJump`, and related options in the normal OpenSSH
configuration.

### Configuration

An automatically populated `~/.config/trdp-config.json` looks like this:

```json
{
  "defaults": {
    "rdpHost": "127.0.0.1",
    "rdpPort": 3389,
    "tunnelReadyTimeoutSeconds": 15,
    "mstscArgs": []
  },
  "hosts": {
    "work": {
      "localAddress": "127.0.42.17"
    },
    "lab": {
      "localAddress": "127.0.93.66",
      "rdpHost": "10.0.0.20",
      "rdpPort": 3390,
      "mstscArgs": ["/f"]
    }
  }
}
```

By default, the remote RDP endpoint is `127.0.0.1:3389` as seen from the SSH
host. Each host can override `rdpHost`, `rdpPort`, and `mstscArgs`.

Use `-Config` to inspect or modify one host:

```powershell
# Show the effective values
trdp work -Config

# Update one or more fields
trdp work -Config -RdpHost 10.0.0.20 -RdpPort 3390
trdp work -Config -LocalAddress 127.0.42.17
trdp work -Config -MstscArgs /f /admin

# Omit values to clear mstscArgs
trdp work -Config -MstscArgs
```

Configuration fields are validated before writing using the same rules applied
when reading the file. Changing `localAddress` also changes the Windows
credential target; credentials stored for the old address are not removed
automatically.

Host entries may be edited or deleted directly. A manually assigned
`localAddress` must have the form `127.0.A.B`, where both A and B are between
`1` and `254`, and it must not duplicate another host's address. Deleting a host
entry does not remove its Windows RDP credentials.

Configuration updates use an inter-process mutex and atomic file replacement,
so concurrent first-time connections cannot allocate duplicate addresses or
overwrite each other's changes.

### RDP credentials

On the first connection, `trdp` prompts for the RDP username and uses Windows
`cmdkey` to read the password without displaying it. The password is stored in
the current user's Windows Credential Manager under `TERMSRV/127.0.A.B`; it is
never written to JSON, logs, or command-line password arguments.

The default RDP username is obtained from the final OpenSSH configuration with
`ssh -G <host>`, so it respects `user@host`, the SSH `User` option, and the
current OpenSSH default user. Press Enter to accept the suggested username, or
enter another one when the SSH and RDP users differ:

```text
RDP username [kurayuri]:
```

Credential operations are also available explicitly:

```powershell
trdp work -Credential Set
trdp work -Credential Set -UserName 'REMOTE-PC\Kurayuri'
trdp work -Credential Status
trdp work -Credential Remove
```

`-Credential Set` can register a new host automatically. `Status` and `Remove`
only display a message for an unregistered host and do not modify the
configuration.

### Connection lifecycle

The forwarding command has this form:

```text
ssh -N -T -o ExitOnForwardFailure=yes \
  -L 127.0.A.B:33389:<rdpHost>:<rdpPort> <host>
```

`trdp` waits for the local listener before starting `mstsc`. Closing the RDP
window terminates the SSH tunnel created for that connection. The script also
cleans up its SSH process if SSH exits early, `mstsc` fails to start, or the
script is interrupted.

### Tests

```powershell
Invoke-Pester .\tests\Connect-TunnelRdp.Tests.ps1
```

The tests support the built-in Pester 3.4 release.

## Connect-SshLocalPortForward (`sshl`)

This script creates a local port forward using the existing OpenSSH
configuration:

```powershell
ish Connect-SshLocalPortForward
sshl work 8080
sshl work 8080 80
```

The arguments are the SSH host, local listening port, and remote `localhost`
port. If the third argument is omitted, the remote port defaults to the local
port. The resulting command has this form:

```text
ssh -L <SourcePort>:localhost:<DestinationPort> <HostName>
```
