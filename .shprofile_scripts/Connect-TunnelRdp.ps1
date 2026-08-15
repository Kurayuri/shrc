[CmdletBinding()]
param(
    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [string[]] $TrdpArguments
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:ConfigPath = Join-Path (Join-Path $HOME '.config') 'trdp-config.json'
$script:LocalPort = 33389
$script:ConfigurationLockTimeoutSeconds = 10

function Write-TrdpUsage {
    @'
trdp - RDP over an OpenSSH tunnel

Usage:
  trdp <host>
  trdp <host> -Tunnel
  trdp <host> -Rdp
  trdp <host> -Credential <Set|Status|Remove> [-UserName <username>]
  trdp <host> -Config [-LocalAddress <127.0.A.B>] [-RdpHost <host>]
                      [-RdpPort <port>] [-MstscArgs <arg> ...]
  trdp --help

The first use of an SSH host automatically assigns and stores a stable
127.0.A.B address in ~/.config/trdp-config.json. Every tunnel uses local port
33389. SSH connection details continue to come from the normal OpenSSH
configuration.

Use -Tunnel to open only the SSH tunnel and keep it running until interrupted.
Use -Rdp to start only mstsc through an already-running tunnel. Without
either option, trdp opens the tunnel and starts mstsc as before.
'@ | Write-Host
}

function Get-OptionalPropertyValue {
    param(
        [AllowNull()] $Object,
        [Parameter(Mandatory = $true)] [string] $Name,
        [AllowNull()] $DefaultValue
    )

    if ($null -eq $Object) {
        return $DefaultValue
    }

    $property = $Object.PSObject.Properties[$Name]
    if (($null -eq $property) -or ($null -eq $property.Value)) {
        return $DefaultValue
    }
    return $property.Value
}

function ConvertTo-ValidatedPort {
    param(
        [Parameter(Mandatory = $true)] $Value,
        [Parameter(Mandatory = $true)] [string] $Name
    )

    $number = 0
    if (-not [int]::TryParse([string]$Value, [ref]$number)) {
        throw "$Name must be an integer; got '$Value'."
    }
    if (($number -lt 1) -or ($number -gt 65535)) {
        throw "$Name must be between 1 and 65535; got '$number'."
    }
    return $number
}

function Assert-JsonObjectProperties {
    param(
        [AllowNull()] $Object,
        [Parameter(Mandatory = $true)] [string] $Path,
        [string[]] $AllowedProperties = @(),
        [switch] $AllowAnyProperty
    )

    if (-not ($Object -is [System.Management.Automation.PSCustomObject])) {
        throw "The '$Path' value in the trdp configuration must be a JSON object."
    }

    foreach ($property in $Object.PSObject.Properties) {
        if (-not $AllowAnyProperty) {
            if ($property.Name -match '^(?i:pass|password|rdpPassword)$') {
                throw "Passwords are not allowed in the trdp configuration. Use 'trdp <host> -Credential Set [-UserName <username>]' instead."
            }
            if ($AllowedProperties -notcontains $property.Name) {
                throw "Unknown trdp configuration property '$Path.$($property.Name)'."
            }
        }
    }
}

function ConvertTo-TrdpHostArgument {
    param([Parameter(Mandatory = $true)] [string] $HostName)

    if ([string]::IsNullOrWhiteSpace($HostName)) {
        throw 'SSH host cannot be empty.'
    }
    if ($HostName.StartsWith('-')) {
        throw "SSH host '$HostName' cannot begin with '-'."
    }
    if ($HostName -match '\s') {
        throw "SSH host '$HostName' cannot contain whitespace."
    }
    if ($HostName -notmatch '^[A-Za-z0-9_.@:%+\-\[\]]+$') {
        throw "SSH host '$HostName' contains unsupported characters."
    }
    return $HostName
}

function ConvertTo-CanonicalHostKey {
    param([Parameter(Mandatory = $true)] [string] $HostName)

    $validated = ConvertTo-TrdpHostArgument -HostName $HostName
    return $validated.ToLowerInvariant()
}

function ConvertTo-ValidatedLocalAddress {
    param(
        [Parameter(Mandatory = $true)] [string] $Address,
        [Parameter(Mandatory = $true)] [string] $Name
    )

    $match = [regex]::Match($Address, '^127\.0\.(\d{1,3})\.(\d{1,3})$')
    if (-not $match.Success) {
        throw "$Name must use the form 127.0.A.B, with A and B from 1 through 254."
    }

    $thirdOctet = [int]$match.Groups[1].Value
    $fourthOctet = [int]$match.Groups[2].Value
    if (($thirdOctet -lt 1) -or ($thirdOctet -gt 254) -or
        ($fourthOctet -lt 1) -or ($fourthOctet -gt 254)) {
        throw "$Name must use the form 127.0.A.B, with A and B from 1 through 254."
    }
    return "127.0.$thirdOctet.$fourthOctet"
}

function ConvertTo-MstscArguments {
    param([AllowNull()] $Value)

    if ($null -eq $Value) {
        return [string[]]@()
    }

    $result = New-Object System.Collections.Generic.List[string]
    foreach ($argument in @($Value)) {
        if (-not ($argument -is [string])) {
            throw 'Every mstscArgs entry must be a string.'
        }
        if (($argument -match '[\r\n"]') -or ($argument -match '\s')) {
            throw "mstscArgs entry '$argument' contains unsupported whitespace or quote characters."
        }
        if (($argument -match '^(?i)/v(?::|$)') -or ($argument -match '^(?i)/edit(?::|$)')) {
            throw "mstscArgs cannot override the RDP target with '$argument'."
        }
        $result.Add($argument)
    }
    return $result.ToArray()
}

function New-EmptyTrdpConfiguration {
    return [pscustomobject]@{
        defaults = [pscustomobject]@{
            rdpHost = '127.0.0.1'
            rdpPort = 3389
            tunnelReadyTimeoutSeconds = 15
            mstscArgs = @()
        }
        hosts = [pscustomobject]@{}
    }
}

function Assert-TrdpConfiguration {
    param([Parameter(Mandatory = $true)] $Configuration)

    Assert-JsonObjectProperties -Object $Configuration -Path '<root>' -AllowedProperties @('defaults', 'hosts')
    Assert-JsonObjectProperties -Object $Configuration.defaults -Path 'defaults' -AllowedProperties @(
        'rdpHost',
        'rdpPort',
        'tunnelReadyTimeoutSeconds',
        'mstscArgs'
    )
    Assert-JsonObjectProperties -Object $Configuration.hosts -Path 'hosts' -AllowAnyProperty

    $seenAliases = @{}
    $seenAddresses = @{}
    foreach ($hostProperty in $Configuration.hosts.PSObject.Properties) {
        ConvertTo-TrdpHostArgument -HostName $hostProperty.Name | Out-Null
        $canonicalAlias = ConvertTo-CanonicalHostKey -HostName $hostProperty.Name
        if ($seenAliases.ContainsKey($canonicalAlias)) {
            throw "The trdp configuration contains duplicate SSH host aliases '$($seenAliases[$canonicalAlias])' and '$($hostProperty.Name)' that differ only by case."
        }
        $seenAliases[$canonicalAlias] = $hostProperty.Name

        Assert-JsonObjectProperties -Object $hostProperty.Value -Path "hosts.$($hostProperty.Name)" -AllowedProperties @(
            'localAddress',
            'rdpHost',
            'rdpPort',
            'mstscArgs'
        )

        $addressProperty = $hostProperty.Value.PSObject.Properties['localAddress']
        if (($null -eq $addressProperty) -or [string]::IsNullOrWhiteSpace([string]$addressProperty.Value)) {
            throw "hosts.$($hostProperty.Name).localAddress is required."
        }
        $address = ConvertTo-ValidatedLocalAddress -Address ([string]$addressProperty.Value) -Name "hosts.$($hostProperty.Name).localAddress"
        if ($seenAddresses.ContainsKey($address)) {
            throw "The trdp configuration assigns local address '$address' to both '$($seenAddresses[$address])' and '$($hostProperty.Name)'."
        }
        $seenAddresses[$address] = $hostProperty.Name

        $rdpHostProperty = $hostProperty.Value.PSObject.Properties['rdpHost']
        if ($null -ne $rdpHostProperty) {
            $rdpHost = [string]$rdpHostProperty.Value
            if ([string]::IsNullOrWhiteSpace($rdpHost) -or ($rdpHost -notmatch '^[A-Za-z0-9_.:%\-\[\]]+$')) {
                throw "hosts.$($hostProperty.Name).rdpHost must be a non-empty host name or address without whitespace."
            }
        }

        $rdpPortProperty = $hostProperty.Value.PSObject.Properties['rdpPort']
        if ($null -ne $rdpPortProperty) {
            ConvertTo-ValidatedPort -Value $rdpPortProperty.Value -Name "hosts.$($hostProperty.Name).rdpPort" | Out-Null
        }

        $mstscArgsProperty = $hostProperty.Value.PSObject.Properties['mstscArgs']
        if ($null -ne $mstscArgsProperty) {
            ConvertTo-MstscArguments -Value $mstscArgsProperty.Value | Out-Null
        }
    }

    $defaultRdpHost = [string](Get-OptionalPropertyValue -Object $Configuration.defaults -Name 'rdpHost' -DefaultValue '127.0.0.1')
    if ([string]::IsNullOrWhiteSpace($defaultRdpHost) -or ($defaultRdpHost -notmatch '^[A-Za-z0-9_.:%\-\[\]]+$')) {
        throw 'defaults.rdpHost must be a non-empty host name or address without whitespace.'
    }
    ConvertTo-ValidatedPort -Value (Get-OptionalPropertyValue -Object $Configuration.defaults -Name 'rdpPort' -DefaultValue 3389) -Name 'defaults.rdpPort' | Out-Null

    $timeout = 0
    $timeoutValue = Get-OptionalPropertyValue -Object $Configuration.defaults -Name 'tunnelReadyTimeoutSeconds' -DefaultValue 15
    if ((-not [int]::TryParse([string]$timeoutValue, [ref]$timeout)) -or ($timeout -lt 1) -or ($timeout -gt 300)) {
        throw 'defaults.tunnelReadyTimeoutSeconds must be an integer from 1 through 300.'
    }
    ConvertTo-MstscArguments -Value (Get-OptionalPropertyValue -Object $Configuration.defaults -Name 'mstscArgs' -DefaultValue @()) | Out-Null
}

function Read-TrdpConfiguration {
    param([string] $Path = $script:ConfigPath)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return New-EmptyTrdpConfiguration
    }

    try {
        $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        if ([string]::IsNullOrWhiteSpace($raw)) {
            throw 'the file is empty'
        }
        $configuration = $raw | ConvertFrom-Json
    }
    catch {
        throw "Unable to read trdp configuration '$Path': $($_.Exception.Message)"
    }

    if (-not ($configuration -is [System.Management.Automation.PSCustomObject])) {
        throw "The trdp configuration '$Path' must contain a JSON object."
    }

    if ($null -eq $configuration.PSObject.Properties['defaults']) {
        $configuration | Add-Member -MemberType NoteProperty -Name defaults -Value ([pscustomobject]@{})
    }
    if ($null -eq $configuration.PSObject.Properties['hosts']) {
        $configuration | Add-Member -MemberType NoteProperty -Name hosts -Value ([pscustomobject]@{})
    }

    Assert-TrdpConfiguration -Configuration $configuration
    return $configuration
}

function Write-TrdpConfiguration {
    param(
        [Parameter(Mandatory = $true)] $Configuration,
        [string] $Path = $script:ConfigPath
    )

    Assert-TrdpConfiguration -Configuration $Configuration
    $directory = Split-Path -Parent ([System.IO.Path]::GetFullPath($Path))
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        try {
            [System.IO.Directory]::CreateDirectory($directory) | Out-Null
        }
        catch {
            throw "Unable to create configuration directory '$directory': $($_.Exception.Message)"
        }
    }

    $temporaryPath = Join-Path $directory ('.trdp-{0}.tmp' -f [Guid]::NewGuid().ToString('N'))
    $backupPath = Join-Path $directory ('.trdp-{0}.bak' -f [Guid]::NewGuid().ToString('N'))
    $json = $Configuration | ConvertTo-Json -Depth 10
    $utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
    try {
        [System.IO.File]::WriteAllText($temporaryPath, ($json + [Environment]::NewLine), $utf8WithoutBom)
        if (Test-Path -LiteralPath $Path -PathType Leaf) {
            [System.IO.File]::Replace($temporaryPath, [System.IO.Path]::GetFullPath($Path), $backupPath, $true)
        }
        else {
            [System.IO.File]::Move($temporaryPath, [System.IO.Path]::GetFullPath($Path))
        }
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) {
            Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path -LiteralPath $backupPath -PathType Leaf) {
            Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Get-ConfigurationMutexName {
    param([Parameter(Mandatory = $true)] [string] $Path)

    $fullPath = [System.IO.Path]::GetFullPath($Path).ToLowerInvariant()
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha256.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($fullPath))
    }
    finally {
        $sha256.Dispose()
    }
    $identifier = ([System.BitConverter]::ToString($hash)).Replace('-', '').Substring(0, 32)
    return "Local\trdp-config-$identifier"
}

function Invoke-WithConfigurationLock {
    param(
        [Parameter(Mandatory = $true)] [string] $Path,
        [Parameter(Mandatory = $true)] [scriptblock] $ScriptBlock
    )

    $mutex = New-Object System.Threading.Mutex($false, (Get-ConfigurationMutexName -Path $Path))
    $acquired = $false
    try {
        try {
            $acquired = $mutex.WaitOne([TimeSpan]::FromSeconds($script:ConfigurationLockTimeoutSeconds))
        }
        catch [System.Threading.AbandonedMutexException] {
            $acquired = $true
        }
        if (-not $acquired) {
            throw "Timed out waiting for exclusive access to '$Path'."
        }
        return & $ScriptBlock
    }
    finally {
        if ($acquired) {
            $mutex.ReleaseMutex()
        }
        $mutex.Dispose()
    }
}

function Find-TrdpHostProperty {
    param(
        [Parameter(Mandatory = $true)] $Hosts,
        [Parameter(Mandatory = $true)] [string] $HostName
    )

    foreach ($property in $Hosts.PSObject.Properties) {
        if ([string]::Equals($property.Name, $HostName, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $property
        }
    }
    return $null
}

function Get-StableLoopbackCandidate {
    param(
        [Parameter(Mandatory = $true)] [string] $CanonicalHost,
        [Parameter(Mandatory = $true)] [int] $Probe
    )

    $hashInput = if ($Probe -eq 0) { $CanonicalHost } else { "$CanonicalHost#$Probe" }
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha256.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($hashInput))
    }
    finally {
        $sha256.Dispose()
    }
    $thirdOctet = 1 + ([int]$hash[0] % 254)
    $fourthOctet = 1 + ([int]$hash[1] % 254)
    return "127.0.$thirdOctet.$fourthOctet"
}

function New-TrdpHostRegistration {
    param(
        [Parameter(Mandatory = $true)] $Configuration,
        [Parameter(Mandatory = $true)] [string] $HostName
    )

    $canonicalHost = ConvertTo-CanonicalHostKey -HostName $HostName
    $usedAddresses = @{}
    foreach ($property in $Configuration.hosts.PSObject.Properties) {
        $usedAddresses[[string]$property.Value.localAddress] = $property.Name
    }

    $address = $null
    for ($probe = 0; $probe -lt (254 * 254); $probe++) {
        $candidate = Get-StableLoopbackCandidate -CanonicalHost $canonicalHost -Probe $probe
        if (-not $usedAddresses.ContainsKey($candidate)) {
            $address = $candidate
            break
        }
    }
    if ($null -eq $address) {
        throw 'No unused trdp loopback address remains in 127.0.1-254.1-254.'
    }

    $registration = [pscustomobject]@{ localAddress = $address }
    $Configuration.hosts | Add-Member -MemberType NoteProperty -Name $HostName -Value $registration
    return $registration
}

function Resolve-TrdpSettings {
    param(
        [Parameter(Mandatory = $true)] [string] $SshHost,
        [Parameter(Mandatory = $true)] $Configuration,
        [Parameter(Mandatory = $true)] $HostProperty
    )

    $defaults = $Configuration.defaults
    $hostConfiguration = $HostProperty.Value

    $rdpHost = [string](Get-OptionalPropertyValue -Object $defaults -Name 'rdpHost' -DefaultValue '127.0.0.1')
    $rdpPort = ConvertTo-ValidatedPort -Value (Get-OptionalPropertyValue -Object $defaults -Name 'rdpPort' -DefaultValue 3389) -Name 'defaults.rdpPort'
    $timeout = [int](Get-OptionalPropertyValue -Object $defaults -Name 'tunnelReadyTimeoutSeconds' -DefaultValue 15)
    $mstscArgs = ConvertTo-MstscArguments -Value (Get-OptionalPropertyValue -Object $defaults -Name 'mstscArgs' -DefaultValue @())

    $rdpHost = [string](Get-OptionalPropertyValue -Object $hostConfiguration -Name 'rdpHost' -DefaultValue $rdpHost)
    $rdpPort = ConvertTo-ValidatedPort -Value (Get-OptionalPropertyValue -Object $hostConfiguration -Name 'rdpPort' -DefaultValue $rdpPort) -Name "hosts.$($HostProperty.Name).rdpPort"
    if ($null -ne $hostConfiguration.PSObject.Properties['mstscArgs']) {
        $mstscArgs = ConvertTo-MstscArguments -Value $hostConfiguration.mstscArgs
    }
    if ([string]::IsNullOrWhiteSpace($rdpHost) -or ($rdpHost -notmatch '^[A-Za-z0-9_.:%\-\[\]]+$')) {
        throw "The RDP host for '$($HostProperty.Name)' must be a non-empty host name or address without whitespace."
    }

    $localAddress = ConvertTo-ValidatedLocalAddress -Address ([string]$hostConfiguration.localAddress) -Name "hosts.$($HostProperty.Name).localAddress"
    return [pscustomobject]@{
        SshHost = $SshHost
        ConfiguredHost = $HostProperty.Name
        LocalAddress = $localAddress
        LocalPort = $script:LocalPort
        RdpHost = $rdpHost
        RdpPort = $rdpPort
        TunnelReadyTimeoutSeconds = $timeout
        MstscArgs = [string[]]$mstscArgs
        CredentialTarget = "TERMSRV/$localAddress"
    }
}

function Get-TrdpSettingsForHost {
    param(
        [Parameter(Mandatory = $true)] [string] $HostName,
        [switch] $RegisterIfMissing,
        [string] $Path = $script:ConfigPath
    )

    $sshHost = ConvertTo-TrdpHostArgument -HostName $HostName
    return Invoke-WithConfigurationLock -Path $Path -ScriptBlock {
        $configuration = Read-TrdpConfiguration -Path $Path
        $hostProperty = Find-TrdpHostProperty -Hosts $configuration.hosts -HostName $sshHost
        if ($null -eq $hostProperty) {
            if (-not $RegisterIfMissing) {
                return $null
            }

            $registration = New-TrdpHostRegistration -Configuration $configuration -HostName $sshHost
            Write-TrdpConfiguration -Configuration $configuration -Path $Path
            Write-Host "Registered SSH host '$sshHost' as $($registration.localAddress):$($script:LocalPort)."
            $hostProperty = Find-TrdpHostProperty -Hosts $configuration.hosts -HostName $sshHost
        }
        return Resolve-TrdpSettings -SshHost $sshHost -Configuration $configuration -HostProperty $hostProperty
    }
}

function Update-TrdpHostConfiguration {
    param(
        [Parameter(Mandatory = $true)] [string] $HostName,
        [Parameter(Mandatory = $true)] [hashtable] $Updates,
        [string] $Path = $script:ConfigPath
    )

    if ($Updates.Count -eq 0) {
        throw 'At least one configuration field must be supplied.'
    }

    $allowedUpdates = @('LocalAddress', 'RdpHost', 'RdpPort', 'MstscArgs')
    foreach ($key in $Updates.Keys) {
        if ($allowedUpdates -notcontains $key) {
            throw "Unknown host configuration field '$key'."
        }
    }

    $sshHost = ConvertTo-TrdpHostArgument -HostName $HostName
    $result = Invoke-WithConfigurationLock -Path $Path -ScriptBlock {
        $configuration = Read-TrdpConfiguration -Path $Path
        $hostProperty = Find-TrdpHostProperty -Hosts $configuration.hosts -HostName $sshHost
        $wasRegistered = $false
        if ($null -eq $hostProperty) {
            New-TrdpHostRegistration -Configuration $configuration -HostName $sshHost | Out-Null
            $hostProperty = Find-TrdpHostProperty -Hosts $configuration.hosts -HostName $sshHost
            $wasRegistered = $true
        }

        $previousLocalAddress = [string]$hostProperty.Value.localAddress
        foreach ($key in $Updates.Keys) {
            switch ($key) {
                'LocalAddress' {
                    $value = ConvertTo-ValidatedLocalAddress -Address ([string]$Updates[$key]) -Name "hosts.$($hostProperty.Name).localAddress"
                    $hostProperty.Value | Add-Member -MemberType NoteProperty -Name localAddress -Value $value -Force
                }
                'RdpHost' {
                    $hostProperty.Value | Add-Member -MemberType NoteProperty -Name rdpHost -Value ([string]$Updates[$key]) -Force
                }
                'RdpPort' {
                    $value = ConvertTo-ValidatedPort -Value $Updates[$key] -Name "hosts.$($hostProperty.Name).rdpPort"
                    $hostProperty.Value | Add-Member -MemberType NoteProperty -Name rdpPort -Value $value -Force
                }
                'MstscArgs' {
                    ConvertTo-MstscArguments -Value $Updates[$key] | Out-Null
                    $value = [string[]]@($Updates[$key])
                    $hostProperty.Value | Add-Member -MemberType NoteProperty -Name mstscArgs -Value $value -Force
                }
            }
        }

        Write-TrdpConfiguration -Configuration $configuration -Path $Path
        return [pscustomobject]@{
            Settings = Resolve-TrdpSettings -SshHost $sshHost -Configuration $configuration -HostProperty $hostProperty
            WasRegistered = $wasRegistered
            PreviousLocalAddress = $previousLocalAddress
        }
    }

    if ($result.WasRegistered) {
        Write-Host "Registered SSH host '$sshHost' as $($result.Settings.LocalAddress):$($script:LocalPort)."
    }
    if ((-not $result.WasRegistered) -and
        ($Updates.ContainsKey('LocalAddress')) -and
        ($result.PreviousLocalAddress -ne $result.Settings.LocalAddress)) {
        Write-Warning "The credential target changed from TERMSRV/$($result.PreviousLocalAddress) to $($result.Settings.CredentialTarget). The old credential was not removed."
    }
    return $result.Settings
}

function Write-TrdpConfigurationStatus {
    param([Parameter(Mandatory = $true)] $Settings)

    $mstscArgs = if (($null -eq $Settings.MstscArgs) -or (@($Settings.MstscArgs).Count -eq 0)) {
        '<none>'
    }
    else {
        @($Settings.MstscArgs) -join ' '
    }
    Write-Host "SSH host:       $($Settings.ConfiguredHost)"
    Write-Host "Local endpoint: $($Settings.LocalAddress):$($Settings.LocalPort)"
    Write-Host "RDP target:     $($Settings.RdpHost):$($Settings.RdpPort)"
    Write-Host "MSTSC args:     $mstscArgs"
}

function Initialize-CredentialNativeMethods {
    if ('Trdp.NativeCredential' -as [type]) {
        return
    }

    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;

namespace Trdp
{
    public static class NativeCredential
    {
        [DllImport("advapi32.dll", EntryPoint = "CredReadW", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool CredRead(string target, uint type, int flags, out IntPtr credential);

        [DllImport("advapi32.dll", SetLastError = false)]
        private static extern void CredFree(IntPtr buffer);

        private static bool ExistsAsType(string target, uint type)
        {
            IntPtr credential;
            if (CredRead(target, type, 0, out credential))
            {
                CredFree(credential);
                return true;
            }

            int error = Marshal.GetLastWin32Error();
            if (error == 1168)
            {
                return false;
            }
            throw new Win32Exception(error);
        }

        public static bool Exists(string target)
        {
            return ExistsAsType(target, 1) || ExistsAsType(target, 2);
        }
    }
}
'@
}

function Test-TrdpCredential {
    param([Parameter(Mandatory = $true)] [string] $Target)

    Initialize-CredentialNativeMethods
    return [Trdp.NativeCredential]::Exists($Target)
}

function ConvertFrom-SshConfigurationUser {
    param([AllowNull()] [string[]] $ConfigurationLines)

    foreach ($line in @($ConfigurationLines)) {
        $match = [regex]::Match([string]$line, '^user\s+(.+?)\s*$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($match.Success) {
            return $match.Groups[1].Value.Trim()
        }
    }
    return ''
}

function Get-ResolvedSshUser {
    param([Parameter(Mandatory = $true)] [string] $HostName)

    ConvertTo-TrdpHostArgument -HostName $HostName | Out-Null
    try {
        $configurationLines = & "$env:SystemRoot\System32\OpenSSH\ssh.exe" -G -T $HostName 2>$null
        if ($LASTEXITCODE -ne 0) {
            return ''
        }
        return ConvertFrom-SshConfigurationUser -ConfigurationLines $configurationLines
    }
    catch {
        return ''
    }
}

function Resolve-RdpUserName {
    param(
        [AllowEmptyString()] [string] $UserName,
        [AllowEmptyString()] [string] $DefaultUserName,
        [Parameter(Mandatory = $true)] [string] $Target
    )

    if (-not [string]::IsNullOrWhiteSpace($UserName)) {
        return $UserName.Trim()
    }

    if (-not [string]::IsNullOrWhiteSpace($DefaultUserName)) {
        $enteredUserName = Read-Host "RDP username [$($DefaultUserName.Trim())]"
        if ([string]::IsNullOrWhiteSpace($enteredUserName)) {
            return $DefaultUserName.Trim()
        }
        return $enteredUserName.Trim()
    }

    $enteredUserName = Read-Host "RDP username for $Target"
    if ([string]::IsNullOrWhiteSpace($enteredUserName)) {
        throw 'RDP username cannot be empty.'
    }
    return $enteredUserName.Trim()
}

function Set-TrdpCredential {
    param(
        [Parameter(Mandatory = $true)] [string] $Target,
        [AllowEmptyString()] [string] $UserName,
        [AllowEmptyString()] [string] $DefaultUserName = ''
    )

    $UserName = Resolve-RdpUserName -UserName $UserName -DefaultUserName $DefaultUserName -Target $Target

    Write-Host "Windows will now request the RDP password for $Target."
    & "$env:SystemRoot\System32\cmdkey.exe" "/generic:$Target" "/user:$UserName" '/pass'
    if ($LASTEXITCODE -ne 0) {
        throw "cmdkey failed to save credential '$Target' (exit code $LASTEXITCODE)."
    }
}

function Remove-TrdpCredential {
    param([Parameter(Mandatory = $true)] [string] $Target)

    if (-not (Test-TrdpCredential -Target $Target)) {
        Write-Host "No credential is stored for $Target."
        return
    }

    & "$env:SystemRoot\System32\cmdkey.exe" "/delete:$Target"
    if ($LASTEXITCODE -ne 0) {
        throw "cmdkey failed to delete credential '$Target' (exit code $LASTEXITCODE)."
    }
}

function Test-LocalEndpointListening {
    param(
        [Parameter(Mandatory = $true)] [string] $Address,
        [Parameter(Mandatory = $true)] [int] $Port,
        [int] $TimeoutMilliseconds = 250
    )

    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $asyncResult = $client.BeginConnect($Address, $Port, $null, $null)
        if (-not $asyncResult.AsyncWaitHandle.WaitOne($TimeoutMilliseconds)) {
            return $false
        }
        try {
            $client.EndConnect($asyncResult)
            return $true
        }
        catch [System.Net.Sockets.SocketException] {
            return $false
        }
    }
    catch [System.Net.Sockets.SocketException] {
        return $false
    }
    finally {
        $client.Dispose()
    }
}

function Assert-LocalEndpointAvailable {
    param(
        [Parameter(Mandatory = $true)] [string] $Address,
        [Parameter(Mandatory = $true)] [int] $Port
    )

    $listener = New-Object System.Net.Sockets.TcpListener ([System.Net.IPAddress]::Parse($Address)), $Port
    try {
        $listener.Server.ExclusiveAddressUse = $true
        $listener.Start()
    }
    catch [System.Net.Sockets.SocketException] {
        throw "Local endpoint ${Address}:$Port is already in use. Close the existing tunnel or application and try again."
    }
    finally {
        try { $listener.Stop() } catch { }
    }
}

function Format-SshForwardTarget {
    param([Parameter(Mandatory = $true)] $Settings)

    $remoteHost = $Settings.RdpHost
    if (($remoteHost -match ':') -and (-not $remoteHost.StartsWith('['))) {
        $remoteHost = "[$remoteHost]"
    }
    return "$($Settings.LocalAddress):$($Settings.LocalPort):${remoteHost}:$($Settings.RdpPort)"
}

function Wait-TrdpTunnel {
    param(
        [Parameter(Mandatory = $true)] $SshProcess,
        [Parameter(Mandatory = $true)] $Settings
    )

    $deadline = [DateTime]::UtcNow.AddSeconds($Settings.TunnelReadyTimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        if ($SshProcess.HasExited) {
            throw "ssh.exe exited before the tunnel became ready (exit code $($SshProcess.ExitCode))."
        }
        if (Test-LocalEndpointListening -Address $Settings.LocalAddress -Port $Settings.LocalPort) {
            return
        }
        Start-Sleep -Milliseconds 100
        $SshProcess.Refresh()
    }
    throw "Timed out after $($Settings.TunnelReadyTimeoutSeconds) seconds waiting for $($Settings.LocalAddress):$($Settings.LocalPort)."
}

function Start-TrdpConnection {
    param([Parameter(Mandatory = $true)] $Settings)

    Assert-LocalEndpointAvailable -Address $Settings.LocalAddress -Port $Settings.LocalPort
    $sshArguments = @(
        '-N',
        '-T',
        '-o', 'ExitOnForwardFailure=yes',
        '-L', (Format-SshForwardTarget -Settings $Settings),
        $Settings.SshHost
    )

    Write-Host "Opening SSH tunnel: $($Settings.SshHost) -> $($Settings.RdpHost):$($Settings.RdpPort)"
    Write-Host "Local RDP endpoint: $($Settings.LocalAddress):$($Settings.LocalPort)"

    $sshProcess = $null
    try {
        $sshProcess = Start-Process -FilePath "$env:SystemRoot\System32\OpenSSH\ssh.exe" -ArgumentList $sshArguments -NoNewWindow -PassThru
        Wait-TrdpTunnel -SshProcess $sshProcess -Settings $Settings
        Start-TrdpClient -Settings $Settings
    }
    finally {
        if (($null -ne $sshProcess) -and (-not $sshProcess.HasExited)) {
            Write-Host 'Closing SSH tunnel.'
            Stop-Process -Id $sshProcess.Id -Force -ErrorAction SilentlyContinue
            try { $sshProcess.WaitForExit(5000) | Out-Null } catch { }
        }
        if ($null -ne $sshProcess) {
            $sshProcess.Dispose()
        }
    }
}

function Start-TrdpClient {
    param([Parameter(Mandatory = $true)] $Settings)

    if (-not (Test-TrdpCredential -Target $Settings.CredentialTarget)) {
        Write-Host "No RDP credential is stored for $($Settings.ConfiguredHost) ($($Settings.CredentialTarget))."
        $defaultUserName = Get-ResolvedSshUser -HostName $Settings.SshHost
        Set-TrdpCredential -Target $Settings.CredentialTarget -UserName '' -DefaultUserName $defaultUserName
    }

    $mstscArguments = New-Object System.Collections.Generic.List[string]
    foreach ($argument in $Settings.MstscArgs) {
        $mstscArguments.Add($argument)
    }
    $mstscArguments.Add("/v:$($Settings.LocalAddress):$($Settings.LocalPort)")

    $mstscProcess = Start-Process -FilePath "$env:SystemRoot\System32\mstsc.exe" -ArgumentList $mstscArguments.ToArray() -PassThru
    $mstscProcess.WaitForExit()
}

function Start-TrdpForward {
    param([Parameter(Mandatory = $true)] $Settings)

    Assert-LocalEndpointAvailable -Address $Settings.LocalAddress -Port $Settings.LocalPort
    $sshArguments = @(
        '-N',
        '-T',
        '-o', 'ExitOnForwardFailure=yes',
        '-L', (Format-SshForwardTarget -Settings $Settings),
        $Settings.SshHost
    )

    Write-Host "Opening SSH tunnel: $($Settings.SshHost) -> $($Settings.RdpHost):$($Settings.RdpPort)"
    Write-Host "Local RDP endpoint: $($Settings.LocalAddress):$($Settings.LocalPort)"
    Write-Host 'Press Ctrl+C to close the SSH tunnel.'

    $sshProcess = $null
    try {
        $sshProcess = Start-Process -FilePath "$env:SystemRoot\System32\OpenSSH\ssh.exe" -ArgumentList $sshArguments -NoNewWindow -PassThru
        Wait-TrdpTunnel -SshProcess $sshProcess -Settings $Settings
        $sshProcess.WaitForExit()
        if ($sshProcess.ExitCode -ne 0) {
            throw "ssh.exe exited with code $($sshProcess.ExitCode)."
        }
    }
    finally {
        if (($null -ne $sshProcess) -and (-not $sshProcess.HasExited)) {
            Write-Host 'Closing SSH tunnel.'
            Stop-Process -Id $sshProcess.Id -Force -ErrorAction SilentlyContinue
            try { $sshProcess.WaitForExit(5000) | Out-Null } catch { }
        }
        if ($null -ne $sshProcess) {
            $sshProcess.Dispose()
        }
    }
}

function Write-UnregisteredHostMessage {
    param([Parameter(Mandatory = $true)] [string] $HostName)

    Write-Host "SSH host '$HostName' is not registered in the trdp configuration."
    Write-Host "Run 'trdp $HostName', 'trdp $HostName -Credential Set', or 'trdp $HostName -Config <field>' to register it."
}

function ConvertFrom-TrdpArguments {
    param([string[]] $Arguments)

    if (($null -eq $Arguments) -or ($Arguments.Count -eq 0) -or ($Arguments[0] -in @('-h', '--help', '/?'))) {
        return [pscustomobject]@{ Mode = 'Help' }
    }

    $items = @($Arguments)
    $hostName = ConvertTo-TrdpHostArgument -HostName $items[0]
    $credentialAction = ''
    $userName = ''
    $userNameSpecified = $false
    $configMode = $false
    $tunnelOnly = $false
    $rdpOnly = $false
    $updates = @{}
    $seenOptions = @{}

    for ($index = 1; $index -lt $items.Count; $index++) {
        $option = $items[$index]
        $optionKey = $option.ToLowerInvariant()
        if ($seenOptions.ContainsKey($optionKey)) {
            throw "Option '$option' was supplied more than once."
        }

        switch ($optionKey) {
            '-credential' {
                $seenOptions[$optionKey] = $true
                $index++
                if ($index -ge $items.Count) {
                    throw "Option '-Credential' requires Set, Status, or Remove."
                }
                $credentialAction = $items[$index]
                if ($credentialAction -notin @('Set', 'Status', 'Remove')) {
                    throw "Unknown credential action '$credentialAction'. Use Set, Status, or Remove."
                }
            }
            '-username' {
                $seenOptions[$optionKey] = $true
                $index++
                if ($index -ge $items.Count) {
                    throw "Option '-UserName' requires a value."
                }
                $userName = $items[$index]
                $userNameSpecified = $true
            }
            '-config' {
                $seenOptions[$optionKey] = $true
                $configMode = $true
            }
            '-tunnel' {
                $seenOptions[$optionKey] = $true
                $tunnelOnly = $true
            }
            '-rdp' {
                $seenOptions[$optionKey] = $true
                $rdpOnly = $true
            }
            '-localaddress' {
                $seenOptions[$optionKey] = $true
                $index++
                if ($index -ge $items.Count) {
                    throw "Option '-LocalAddress' requires a value."
                }
                $updates['LocalAddress'] = $items[$index]
            }
            '-rdphost' {
                $seenOptions[$optionKey] = $true
                $index++
                if ($index -ge $items.Count) {
                    throw "Option '-RdpHost' requires a value."
                }
                $updates['RdpHost'] = $items[$index]
            }
            '-rdpport' {
                $seenOptions[$optionKey] = $true
                $index++
                if ($index -ge $items.Count) {
                    throw "Option '-RdpPort' requires a value."
                }
                $updates['RdpPort'] = $items[$index]
            }
            '-mstscargs' {
                $seenOptions[$optionKey] = $true
                $argumentsForMstsc = New-Object System.Collections.Generic.List[string]
                while (($index + 1) -lt $items.Count) {
                    $candidate = $items[$index + 1]
                    if ($candidate.StartsWith('-')) {
                        break
                    }
                    $index++
                    foreach ($value in @($candidate -split ',')) {
                        if (-not [string]::IsNullOrEmpty($value)) {
                            $argumentsForMstsc.Add($value)
                        }
                    }
                }
                $updates['MstscArgs'] = [string[]]$argumentsForMstsc.ToArray()
            }
            default {
                throw "Unknown option '$option'. Options after the SSH host must use names such as -Credential or -Config."
            }
        }
    }

    if ((-not [string]::IsNullOrEmpty($credentialAction)) -and $configMode) {
        throw "Options '-Credential' and '-Config' cannot be used together."
    }
    if ($tunnelOnly -and $rdpOnly) {
        throw "Options '-Tunnel' and '-Rdp' cannot be used together."
    }
    if (($tunnelOnly -or $rdpOnly) -and
        (($configMode) -or (-not [string]::IsNullOrEmpty($credentialAction)))) {
        throw "Options '-Tunnel' and '-Rdp' cannot be combined with '-Credential' or '-Config'."
    }
    if (($updates.Count -gt 0) -and (-not $configMode)) {
        throw "Configuration fields require the '-Config' option."
    }
    if ($userNameSpecified -and ($credentialAction -ine 'Set')) {
        throw "Option '-UserName' can only be used with '-Credential Set'."
    }

    $mode = if (-not [string]::IsNullOrEmpty($credentialAction)) {
        'Credential'
    }
    elseif ($configMode) {
        'Config'
    }
    elseif ($tunnelOnly) {
        'Tunnel'
    }
    elseif ($rdpOnly) {
        'Rdp'
    }
    else {
        'Connect'
    }

    return [pscustomobject]@{
        Mode = $mode
        HostName = $hostName
        CredentialAction = $credentialAction
        UserName = $userName
        Updates = $updates
    }
}

function Invoke-Trdp {
    param([string[]] $Arguments)

    $command = ConvertFrom-TrdpArguments -Arguments $Arguments
    switch ($command.Mode) {
        'Help' {
            Write-TrdpUsage
        }
        'Connect' {
            $settings = Get-TrdpSettingsForHost -HostName $command.HostName -RegisterIfMissing
            Start-TrdpConnection -Settings $settings
        }
        'Tunnel' {
            $settings = Get-TrdpSettingsForHost -HostName $command.HostName -RegisterIfMissing
            Start-TrdpForward -Settings $settings
        }
        'Rdp' {
            $settings = Get-TrdpSettingsForHost -HostName $command.HostName
            if ($null -eq $settings) {
                Write-UnregisteredHostMessage -HostName $command.HostName
                return
            }
            if (-not (Test-LocalEndpointListening -Address $settings.LocalAddress -Port $settings.LocalPort)) {
                throw "No tunnel is listening on $($settings.LocalAddress):$($settings.LocalPort). Run 'trdp $($command.HostName) -Tunnel' first."
            }
            Start-TrdpClient -Settings $settings
        }
        'Config' {
            if ($command.Updates.Count -gt 0) {
                $settings = Update-TrdpHostConfiguration -HostName $command.HostName -Updates $command.Updates
            }
            else {
                $settings = Get-TrdpSettingsForHost -HostName $command.HostName
                if ($null -eq $settings) {
                    Write-UnregisteredHostMessage -HostName $command.HostName
                    return
                }
            }
            Write-TrdpConfigurationStatus -Settings $settings
        }
        'Credential' {
            switch ($command.CredentialAction.ToLowerInvariant()) {
                'set' {
                    $settings = Get-TrdpSettingsForHost -HostName $command.HostName -RegisterIfMissing
                    $defaultUserName = if ([string]::IsNullOrWhiteSpace($command.UserName)) {
                        Get-ResolvedSshUser -HostName $settings.SshHost
                    }
                    else {
                        ''
                    }
                    Set-TrdpCredential -Target $settings.CredentialTarget -UserName $command.UserName -DefaultUserName $defaultUserName
                }
                'status' {
                    $settings = Get-TrdpSettingsForHost -HostName $command.HostName
                    if ($null -eq $settings) {
                        Write-UnregisteredHostMessage -HostName $command.HostName
                        return
                    }
                    $exists = Test-TrdpCredential -Target $settings.CredentialTarget
                    Write-Host "SSH host:          $($settings.ConfiguredHost)"
                    Write-Host "Local endpoint:    $($settings.LocalAddress):$($settings.LocalPort)"
                    Write-Host "Credential target: $($settings.CredentialTarget)"
                    Write-Host "Credential stored: $exists"
                }
                'remove' {
                    $settings = Get-TrdpSettingsForHost -HostName $command.HostName
                    if ($null -eq $settings) {
                        Write-UnregisteredHostMessage -HostName $command.HostName
                        return
                    }
                    Remove-TrdpCredential -Target $settings.CredentialTarget
                }
            }
        }
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    try {
        Invoke-Trdp -Arguments $TrdpArguments
    }
    catch {
        Write-Error $_.Exception.Message
        exit 1
    }
}
