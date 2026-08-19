$repositoryRoot = Split-Path $PSScriptRoot -Parent
$shProfileScriptsRoot = Join-Path $repositoryRoot '.shprofile_scripts'
$trdpScriptUnderTest = Join-Path $shProfileScriptsRoot 'Connect-TunnelRdp.ps1'
. $trdpScriptUnderTest

function New-TestConfiguration {
    param(
        $Defaults = $null,
        $Hosts = $null
    )

    if ($null -eq $Defaults) { $Defaults = [pscustomobject]@{} }
    if ($null -eq $Hosts) { $Hosts = [pscustomobject]@{} }
    return [pscustomobject]@{ defaults = $Defaults; hosts = $Hosts }
}

function Write-TestConfiguration {
    param(
        [Parameter(Mandatory = $true)] [string] $Path,
        [Parameter(Mandatory = $true)] $Configuration
    )

    $Configuration | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $Path -Encoding UTF8
}

Describe 'stable trdp address generation' {
    It 'generates the same valid address for the same canonical host' {
        $first = Get-StableLoopbackCandidate -CanonicalHost 'work' -Probe 0
        $second = Get-StableLoopbackCandidate -CanonicalHost 'work' -Probe 0
        $first | Should Be $second
        { ConvertTo-ValidatedLocalAddress -Address $first -Name 'test' } | Should Not Throw
    }

    It 'treats host aliases case-insensitively' {
        (ConvertTo-CanonicalHostKey -HostName 'My-Work') | Should Be 'my-work'
    }

    It 'rejects addresses outside the managed 127.0.A.B range' {
        { ConvertTo-ValidatedLocalAddress -Address '127.0.0.2' -Name 'test' } | Should Throw
        { ConvertTo-ValidatedLocalAddress -Address '127.1.2.3' -Name 'test' } | Should Throw
        { ConvertTo-ValidatedLocalAddress -Address '127.0.2.255' -Name 'test' } | Should Throw
    }

    It 'rejects unsafe host argument characters' {
        { ConvertTo-TrdpHostArgument -HostName 'host"-oProxyCommand=bad' } | Should Throw
        { ConvertTo-TrdpHostArgument -HostName 'host name' } | Should Throw
    }
}

Describe 'automatic host registration' {
    It 'registers an arbitrary SSH alias immediately' {
        $path = Join-Path $TestDrive 'register.json'
        Write-TestConfiguration -Path $path -Configuration (New-TestConfiguration)

        $settings = Get-TrdpSettingsForHost -HostName 'work' -RegisterIfMissing -Path $path
        $stored = Read-TrdpConfiguration -Path $path

        $stored.hosts.work.localAddress | Should Be $settings.LocalAddress
        $settings.LocalPort | Should Be 33389
        $settings.CredentialTarget | Should Be "TERMSRV/$($settings.LocalAddress)"
    }

    It 'reuses the registration without adding a differently cased duplicate' {
        $path = Join-Path $TestDrive 'case.json'
        Write-TestConfiguration -Path $path -Configuration (New-TestConfiguration)

        $first = Get-TrdpSettingsForHost -HostName 'Work' -RegisterIfMissing -Path $path
        $second = Get-TrdpSettingsForHost -HostName 'wORK' -RegisterIfMissing -Path $path
        $stored = Read-TrdpConfiguration -Path $path

        $second.LocalAddress | Should Be $first.LocalAddress
        @($stored.hosts.PSObject.Properties).Count | Should Be 1
        @($stored.hosts.PSObject.Properties)[0].Name | Should Be 'Work'
    }

    It 'resolves a hash collision by probing another address' {
        $path = Join-Path $TestDrive 'collision.json'
        $hosts = [pscustomobject]@{
            first = [pscustomobject]@{ localAddress = '127.0.10.10' }
        }
        Write-TestConfiguration -Path $path -Configuration (New-TestConfiguration -Hosts $hosts)
        Mock Get-StableLoopbackCandidate {
            param($CanonicalHost, $Probe)
            if ($Probe -eq 0) { return '127.0.10.10' }
            return '127.0.10.11'
        }

        $settings = Get-TrdpSettingsForHost -HostName 'second' -RegisterIfMissing -Path $path
        $settings.LocalAddress | Should Be '127.0.10.11'
    }

    It 'does not register an unknown host during a read-only lookup' {
        $path = Join-Path $TestDrive 'readonly.json'
        Write-TestConfiguration -Path $path -Configuration (New-TestConfiguration)

        $settings = Get-TrdpSettingsForHost -HostName 'unknown' -Path $path
        $stored = Read-TrdpConfiguration -Path $path

        $settings | Should BeNullOrEmpty
        @($stored.hosts.PSObject.Properties).Count | Should Be 0
    }

    It 'serializes registrations from two PowerShell processes' {
        $concurrencyTestDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ('trdp-pester-' + [Guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $concurrencyTestDirectory | Out-Null
        $path = Join-Path $concurrencyTestDirectory 'concurrent.json'
        $resolvedTrdpScript = (Resolve-Path -LiteralPath $trdpScriptUnderTest).Path
        Write-TestConfiguration -Path $path -Configuration (New-TestConfiguration)
        $jobs = @()
        try {
            $jobs += Start-Job -ScriptBlock {
                param($TrdpScript, $TargetConfigPath, $HostName)
                try {
                    . $TrdpScript
                    $settings = Get-TrdpSettingsForHost -HostName $HostName -RegisterIfMissing -Path $TargetConfigPath
                    [pscustomobject]@{ Success = $true; Address = $settings.LocalAddress; Error = ''; ConfigPath = $TargetConfigPath }
                }
                catch {
                    [pscustomobject]@{ Success = $false; Address = ''; Error = $_.Exception.Message; ConfigPath = $TargetConfigPath }
                }
            } -ArgumentList $resolvedTrdpScript, $path, 'concurrent-one'
            $jobs += Start-Job -ScriptBlock {
                param($TrdpScript, $TargetConfigPath, $HostName)
                try {
                    . $TrdpScript
                    $settings = Get-TrdpSettingsForHost -HostName $HostName -RegisterIfMissing -Path $TargetConfigPath
                    [pscustomobject]@{ Success = $true; Address = $settings.LocalAddress; Error = ''; ConfigPath = $TargetConfigPath }
                }
                catch {
                    [pscustomobject]@{ Success = $false; Address = ''; Error = $_.Exception.Message; ConfigPath = $TargetConfigPath }
                }
            } -ArgumentList $resolvedTrdpScript, $path, 'concurrent-two'

            $jobs | Wait-Job -Timeout 20 | Out-Null
            foreach ($job in $jobs) {
                $job.State | Should Be 'Completed'
                $jobResult = Receive-Job -Job $job
                $jobResult.Success | Should Be $true
                $jobResult.Error | Should Be ''
                $jobResult.ConfigPath | Should Be $path
            }

            $stored = Read-TrdpConfiguration -Path $path
            @($stored.hosts.PSObject.Properties).Count | Should Be 2
            $stored.hosts.'concurrent-one'.localAddress | Should Not Be $stored.hosts.'concurrent-two'.localAddress
        }
        finally {
            $jobs | Remove-Job -Force -ErrorAction SilentlyContinue
            $resolvedTestDirectory = [System.IO.Path]::GetFullPath($concurrencyTestDirectory)
            $resolvedTempDirectory = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
            if ($resolvedTestDirectory.StartsWith($resolvedTempDirectory) -and
                ([System.IO.Path]::GetFileName($resolvedTestDirectory) -like 'trdp-pester-*')) {
                Remove-Item -LiteralPath $resolvedTestDirectory -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

Describe 'trdp configuration validation' {
    It 'reads the new default configuration shape' {
        $path = Join-Path $TestDrive 'default.json'
        '{"defaults":{"rdpHost":"127.0.0.1","rdpPort":3389,"tunnelReadyTimeoutSeconds":15,"mstscArgs":[]},"hosts":{}}' | Set-Content -LiteralPath $path -Encoding UTF8
        { Read-TrdpConfiguration -Path $path } | Should Not Throw
    }

    It 'applies host-specific RDP target overrides' {
        $hosts = [pscustomobject]@{
            lab = [pscustomobject]@{
                localAddress = '127.0.20.30'
                rdpHost = '10.0.0.20'
                rdpPort = 3390
            }
        }
        $configuration = New-TestConfiguration -Hosts $hosts
        Assert-TrdpConfiguration -Configuration $configuration
        $property = Find-TrdpHostProperty -Hosts $configuration.hosts -HostName 'lab'
        $settings = Resolve-TrdpSettings -SshHost 'lab' -Configuration $configuration -HostProperty $property

        $settings.RdpHost | Should Be '10.0.0.20'
        $settings.RdpPort | Should Be 3390
        (Format-SshForwardTarget -Settings $settings) | Should Be '127.0.20.30:33389:10.0.0.20:3390'
    }

    It 'rejects duplicate local addresses' {
        $hosts = [pscustomobject]@{
            one = [pscustomobject]@{ localAddress = '127.0.2.3' }
            two = [pscustomobject]@{ localAddress = '127.0.2.3' }
        }
        { Assert-TrdpConfiguration -Configuration (New-TestConfiguration -Hosts $hosts) } | Should Throw
    }

    It 'rejects aliases that differ only by case' {
        $path = Join-Path $TestDrive 'duplicate-case.json'
        '{"defaults":{},"hosts":{"Work":{"localAddress":"127.0.2.3"},"work":{"localAddress":"127.0.2.4"}}}' | Set-Content -LiteralPath $path -Encoding UTF8
        { Read-TrdpConfiguration -Path $path } | Should Throw
    }

    It 'rejects password and unknown properties' {
        $passwordHosts = [pscustomobject]@{
            work = [pscustomobject]@{ localAddress = '127.0.2.3'; password = 'secret' }
        }
        { Assert-TrdpConfiguration -Configuration (New-TestConfiguration -Hosts $passwordHosts) } | Should Throw

        $unknownDefaults = [pscustomobject]@{ rdpPrt = 3389 }
        { Assert-TrdpConfiguration -Configuration (New-TestConfiguration -Defaults $unknownDefaults) } | Should Throw
    }

    It 'rejects mstsc target overrides' {
        $defaults = [pscustomobject]@{ mstscArgs = @('/v:elsewhere') }
        { Assert-TrdpConfiguration -Configuration (New-TestConfiguration -Defaults $defaults) } | Should Throw
    }

    It 'validates host-specific RDP target overrides' {
        $invalidHost = [pscustomobject]@{
            work = [pscustomobject]@{ localAddress = '127.0.2.3'; rdpHost = 'bad host' }
        }
        $invalidPort = [pscustomobject]@{
            work = [pscustomobject]@{ localAddress = '127.0.2.3'; rdpPort = 70000 }
        }
        $invalidMstscArgs = [pscustomobject]@{
            work = [pscustomobject]@{ localAddress = '127.0.2.3'; mstscArgs = @('/v:elsewhere') }
        }

        { Assert-TrdpConfiguration -Configuration (New-TestConfiguration -Hosts $invalidHost) } | Should Throw
        { Assert-TrdpConfiguration -Configuration (New-TestConfiguration -Hosts $invalidPort) } | Should Throw
        { Assert-TrdpConfiguration -Configuration (New-TestConfiguration -Hosts $invalidMstscArgs) } | Should Throw
    }

    It 'writes a parseable replacement without temporary files' {
        $path = Join-Path $TestDrive 'atomic.json'
        Write-TestConfiguration -Path $path -Configuration (New-TestConfiguration)
        $configuration = Read-TrdpConfiguration -Path $path
        New-TrdpHostRegistration -Configuration $configuration -HostName 'work' | Out-Null
        Write-TrdpConfiguration -Configuration $configuration -Path $path

        { Read-TrdpConfiguration -Path $path } | Should Not Throw
        @(Get-ChildItem -LiteralPath $TestDrive -Filter '.trdp-*.tmp').Count | Should Be 0
        @(Get-ChildItem -LiteralPath $TestDrive -Filter '.trdp-*.bak').Count | Should Be 0
    }
}

Describe 'trdp named command arguments' {
    It 'treats the first positional argument as the SSH host' {
        $command = ConvertFrom-TrdpArguments -Arguments @('credential')

        $command.Mode | Should Be 'Connect'
        $command.HostName | Should Be 'credential'
    }

    It 'parses credential operations after the host' {
        $command = ConvertFrom-TrdpArguments -Arguments @('work', '-Credential', 'Set', '-UserName', 'DOMAIN\User')

        $command.Mode | Should Be 'Credential'
        $command.HostName | Should Be 'work'
        $command.CredentialAction | Should Be 'Set'
        $command.UserName | Should Be 'DOMAIN\User'
    }

    It 'parses host configuration fields and multiple mstsc arguments' {
        $command = ConvertFrom-TrdpArguments -Arguments @(
            'lab',
            '-Config',
            '-LocalAddress', '127.0.20.31',
            '-RdpHost', '10.0.0.20',
            '-RdpPort', '3390',
            '-MstscArgs', '/f', '/admin'
        )

        $command.Mode | Should Be 'Config'
        $command.Updates.LocalAddress | Should Be '127.0.20.31'
        $command.Updates.RdpHost | Should Be '10.0.0.20'
        $command.Updates.RdpPort | Should Be '3390'
        @($command.Updates.MstscArgs).Count | Should Be 2
        $command.Updates.MstscArgs[0] | Should Be '/f'
        $command.Updates.MstscArgs[1] | Should Be '/admin'
    }

    It 'allows an empty mstsc argument list to clear the override' {
        $command = ConvertFrom-TrdpArguments -Arguments @('lab', '-Config', '-MstscArgs')

        $command.Updates.ContainsKey('MstscArgs') | Should Be $true
        @($command.Updates.MstscArgs).Count | Should Be 0
    }

    It 'rejects incompatible or misplaced options' {
        { ConvertFrom-TrdpArguments -Arguments @('work', '-Credential', 'Status', '-Config') } | Should Throw
        { ConvertFrom-TrdpArguments -Arguments @('work', '-Credential', 'Remove', '-UserName', 'User') } | Should Throw
        { ConvertFrom-TrdpArguments -Arguments @('work', '-RdpPort', '3390') } | Should Throw
        { ConvertFrom-TrdpArguments -Arguments @('work', 'status') } | Should Throw
    }
}

Describe 'host configuration updates' {
    It 'registers a host and atomically stores validated field updates' {
        $path = Join-Path $TestDrive 'update.json'
        Write-TestConfiguration -Path $path -Configuration (New-TestConfiguration)
        $updates = @{
            RdpHost = '10.0.0.20'
            RdpPort = '3390'
            MstscArgs = @('/f', '/admin')
        }

        $settings = Update-TrdpHostConfiguration -HostName 'lab' -Updates $updates -Path $path
        $stored = Read-TrdpConfiguration -Path $path

        $settings.RdpHost | Should Be '10.0.0.20'
        $settings.RdpPort | Should Be 3390
        @($settings.MstscArgs).Count | Should Be 2
        $stored.hosts.lab.rdpHost | Should Be '10.0.0.20'
        $stored.hosts.lab.rdpPort | Should Be 3390
        @($stored.hosts.lab.mstscArgs).Count | Should Be 2
    }

    It 'updates an existing registration without changing its local address' {
        $path = Join-Path $TestDrive 'existing.json'
        $hosts = [pscustomobject]@{
            Work = [pscustomobject]@{ localAddress = '127.0.20.30' }
        }
        Write-TestConfiguration -Path $path -Configuration (New-TestConfiguration -Hosts $hosts)

        $settings = Update-TrdpHostConfiguration -HostName 'work' -Updates @{ RdpPort = 3390 } -Path $path
        $stored = Read-TrdpConfiguration -Path $path

        $settings.ConfiguredHost | Should Be 'Work'
        $settings.LocalAddress | Should Be '127.0.20.30'
        @($stored.hosts.PSObject.Properties).Count | Should Be 1
    }

    It 'does not write an invalid update' {
        $path = Join-Path $TestDrive 'invalid-update.json'
        $hosts = [pscustomobject]@{
            work = [pscustomobject]@{ localAddress = '127.0.20.30'; rdpPort = 3389 }
        }
        Write-TestConfiguration -Path $path -Configuration (New-TestConfiguration -Hosts $hosts)

        { Update-TrdpHostConfiguration -HostName 'work' -Updates @{ RdpPort = 70000 } -Path $path } | Should Throw
        $stored = Read-TrdpConfiguration -Path $path
        $stored.hosts.work.rdpPort | Should Be 3389
    }

    It 'does not write an invalid RDP host update' {
        $path = Join-Path $TestDrive 'invalid-host-update.json'
        $hosts = [pscustomobject]@{
            work = [pscustomobject]@{ localAddress = '127.0.20.30'; rdpHost = '127.0.0.1' }
        }
        Write-TestConfiguration -Path $path -Configuration (New-TestConfiguration -Hosts $hosts)

        { Update-TrdpHostConfiguration -HostName 'work' -Updates @{ RdpHost = 'bad host' } -Path $path } | Should Throw
        $stored = Read-TrdpConfiguration -Path $path
        $stored.hosts.work.rdpHost | Should Be '127.0.0.1'
    }

    It 'stores an empty mstsc argument array when clearing it' {
        $path = Join-Path $TestDrive 'clear-mstsc.json'
        $hosts = [pscustomobject]@{
            work = [pscustomobject]@{ localAddress = '127.0.20.30'; mstscArgs = @('/f') }
        }
        Write-TestConfiguration -Path $path -Configuration (New-TestConfiguration -Hosts $hosts)

        Update-TrdpHostConfiguration -HostName 'work' -Updates @{ MstscArgs = [string[]]@() } -Path $path | Out-Null
        $raw = Get-Content -LiteralPath $path -Raw -Encoding UTF8
        $raw | Should Match '"mstscArgs"\s*:\s*\[\s*\]'
    }

    It 'rejects a duplicate local address without writing it' {
        $path = Join-Path $TestDrive 'duplicate-update.json'
        $hosts = [pscustomobject]@{
            one = [pscustomobject]@{ localAddress = '127.0.20.30' }
            two = [pscustomobject]@{ localAddress = '127.0.20.31' }
        }
        Write-TestConfiguration -Path $path -Configuration (New-TestConfiguration -Hosts $hosts)

        { Update-TrdpHostConfiguration -HostName 'two' -Updates @{ LocalAddress = '127.0.20.30' } -Path $path } | Should Throw
        $stored = Read-TrdpConfiguration -Path $path
        $stored.hosts.two.localAddress | Should Be '127.0.20.31'
    }
}

Describe 'fixed local endpoint behavior' {
    It 'can bind port 33389 independently on different loopback addresses' {
        $first = New-Object System.Net.Sockets.TcpListener ([System.Net.IPAddress]::Parse('127.0.20.30')), 33389
        $second = New-Object System.Net.Sockets.TcpListener ([System.Net.IPAddress]::Parse('127.0.20.31')), 33389
        try {
            $first.Start()
            $second.Start()
            $first.LocalEndpoint.Port | Should Be 33389
            $second.LocalEndpoint.Port | Should Be 33389
        }
        finally {
            $first.Stop()
            $second.Stop()
        }
    }

    It 'detects an occupied host endpoint' {
        $listener = New-Object System.Net.Sockets.TcpListener ([System.Net.IPAddress]::Parse('127.0.20.30')), 33389
        try {
            $listener.Start()
            { Assert-LocalEndpointAvailable -Address '127.0.20.30' -Port 33389 } | Should Throw
        }
        finally {
            $listener.Stop()
        }
    }
}

Describe 'RDP username defaults' {
    It 'parses the resolved OpenSSH user' {
        $lines = @('hostname example', 'user kurayuri', 'port 22')
        (ConvertFrom-SshConfigurationUser -ConfigurationLines $lines) | Should Be 'kurayuri'
    }

    It 'accepts the OpenSSH user when Enter is pressed' {
        Mock Read-Host { return '' }
        $resolved = Resolve-RdpUserName -UserName '' -DefaultUserName 'kurayuri' -Target 'TERMSRV/127.0.1.2'
        $resolved | Should Be 'kurayuri'
        Assert-MockCalled Read-Host -Times 1 -Exactly -Scope It -ParameterFilter { $Prompt -eq 'RDP username [kurayuri]' }
    }

    It 'allows the prompted RDP user to override the OpenSSH user' {
        Mock Read-Host { return 'REMOTE-PC\OtherUser' }
        $resolved = Resolve-RdpUserName -UserName '' -DefaultUserName 'kurayuri' -Target 'TERMSRV/127.0.1.2'
        $resolved | Should Be 'REMOTE-PC\OtherUser'
    }

    It 'does not prompt when a username is supplied explicitly' {
        Mock Read-Host { throw 'Read-Host should not be called' }
        $resolved = Resolve-RdpUserName -UserName 'DOMAIN\ExplicitUser' -DefaultUserName 'kurayuri' -Target 'TERMSRV/127.0.1.2'
        $resolved | Should Be 'DOMAIN\ExplicitUser'
        Assert-MockCalled Read-Host -Times 0 -Exactly -Scope It
    }
}

Describe 'trdp connection lifecycle' {
    BeforeEach {
        $script:fakeSshProcess = [pscustomobject]@{ HasExited = $false; Id = 42420 }
        $script:fakeSshProcess | Add-Member -MemberType ScriptMethod -Name WaitForExit -Value { param($milliseconds) return $true }
        $script:fakeSshProcess | Add-Member -MemberType ScriptMethod -Name Dispose -Value { }

        $script:fakeMstscProcess = [pscustomobject]@{ HasExited = $false; Id = 42421 }
        $script:fakeMstscProcess | Add-Member -MemberType ScriptMethod -Name WaitForExit -Value { }

        Mock Test-TrdpCredential { return $true }
        Mock Assert-LocalEndpointAvailable { }
        Mock Wait-TrdpTunnel { }
        Mock Stop-Process { }
        Mock Start-Process {
            param($FilePath)
            if ($FilePath -like '*ssh.exe') {
                return $script:fakeSshProcess
            }
            return $script:fakeMstscProcess
        }
    }

    It 'starts SSH and mstsc, then stops the tunnel when mstsc exits' {
        $hosts = [pscustomobject]@{ work = [pscustomobject]@{ localAddress = '127.0.20.30' } }
        $configuration = New-TestConfiguration -Hosts $hosts
        $property = Find-TrdpHostProperty -Hosts $configuration.hosts -HostName 'work'
        $settings = Resolve-TrdpSettings -SshHost 'work' -Configuration $configuration -HostProperty $property

        Start-TrdpConnection -Settings $settings

        Assert-MockCalled Start-Process -Times 2 -Exactly -Scope It
        Assert-MockCalled Wait-TrdpTunnel -Times 1 -Exactly -Scope It
        Assert-MockCalled Stop-Process -Times 1 -Exactly -Scope It -ParameterFilter { $Id -eq 42420 -and $Force }
    }

    It 'uses the resolved SSH user as the default when credentials are missing' {
        Mock Test-TrdpCredential { return $false }
        Mock Get-ResolvedSshUser { return 'kurayuri' }
        Mock Set-TrdpCredential { }

        $hosts = [pscustomobject]@{ work = [pscustomobject]@{ localAddress = '127.0.20.30' } }
        $configuration = New-TestConfiguration -Hosts $hosts
        $property = Find-TrdpHostProperty -Hosts $configuration.hosts -HostName 'work'
        $settings = Resolve-TrdpSettings -SshHost 'work' -Configuration $configuration -HostProperty $property

        Start-TrdpConnection -Settings $settings

        Assert-MockCalled Get-ResolvedSshUser -Times 1 -Exactly -Scope It -ParameterFilter { $HostName -eq 'work' }
        Assert-MockCalled Set-TrdpCredential -Times 1 -Exactly -Scope It -ParameterFilter {
            $Target -eq 'TERMSRV/127.0.20.30' -and $UserName -eq '' -and $DefaultUserName -eq 'kurayuri'
        }
    }

    It 'stops the SSH tunnel when mstsc fails to start' {
        Mock Start-Process {
            param($FilePath)
            if ($FilePath -like '*ssh.exe') {
                return $script:fakeSshProcess
            }
            throw 'mstsc failed'
        }

        $hosts = [pscustomobject]@{ work = [pscustomobject]@{ localAddress = '127.0.20.30' } }
        $configuration = New-TestConfiguration -Hosts $hosts
        $property = Find-TrdpHostProperty -Hosts $configuration.hosts -HostName 'work'
        $settings = Resolve-TrdpSettings -SshHost 'work' -Configuration $configuration -HostProperty $property

        { Start-TrdpConnection -Settings $settings } | Should Throw
        Assert-MockCalled Stop-Process -Times 1 -Exactly -Scope It -ParameterFilter { $Id -eq 42420 -and $Force }
    }
}
