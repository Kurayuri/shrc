################################################################
# # PowerShell Run Commands
################################################################

################################################################
# # Env
$ShProfilePath = Join-Path $HOME ".shprofile.ps1"
$ShProfileScriptsHome = Join-Path $HOME ".shprofile_scripts"
$ShProfileRepoRawUrl = "https://gitee.com/kurayuri/shrc/raw/main"
$ShProfileScriptsManifestUrl = "$ShProfileRepoRawUrl/.shprofile_scripts/manifest.txt"

################################################################
# # Settings
Set-PSReadlineKeyHandler -Key Tab -Function MenuComplete

################################################################
# # Alias
Set-Alias which Get-Command
Set-Alias gh Get-Help

function Get-AllChildItem { Get-ChildItem -Force @args }
Set-Alias l  Get-AllChildItem
Set-Alias la  Get-AllChildItem
Set-Alias ll  Get-ChildItem

Set-Alias G Select-String
Set-Alias S Select-Object


Set-Alias py python
Set-Alias ipy ipython


################################################################
# # Prompt
function Prompt {
  $loc = $executionContext.SessionState.Path.CurrentLocation;

  $out = ""
  if ($loc.Provider.Name -eq "FileSystem") {
    $out += "$([char]27)]9;9;`"$($loc.ProviderPath)`"$([char]27)\"
  }
  $out += "PS $loc$('>' * ($nestedPromptLevel + 1)) ";
  return $out
}

################################################################
# # Anaconda
If (Test-Path "$Env:CONDA_HOME\Scripts\conda.exe") {
  function Initialize-Conda { & "$ENV:CONDA_HOME\shell\condabin\conda-hook.ps1" }
  function Invoke-CondaAbbr {
    param (
      [string]$command
    )
    $arg0 = $args[0]
    $arg1 = $args[1]
    $args_ = $args | Select-Object -Skip 2

    if (-not $command) {
      conda
    }

    switch ($command) {
      "av" { conda activate @args }
      "dv" { conda deactivate @args }
      "l" { conda env list @args }
      "n" { conda create @args }
      "nn" { conda create -n @args python }
      "nnp" { conda create -n $arg0 @args_ python=$arg1 }
      "rm" { conda env remove -n @args }
      default { conda $args }
    }
  }

  function Enter-Conda { conda activate @args }
  function Exit-Conda { conda deactivate @args }

  Set-Alias cn Invoke-CondaAbbr
  Set-Alias cni Initialize-Conda
  Set-Alias cav Enter-Conda
  Set-Alias cdv Exit-Conda

  Initialize-Conda
}

################################################################
# # Shortcut
function ConvertFrom-Shortcut {
  param (
    [string]$Path = $null,
    [string]$ItemType = "SymbolicLink"
  )

  if (Test-Path $Path -PathType Leaf) {
    $Filter = "*"
  }
  else {
    $Filter = "*.lnk"
  }

  Get-ChildItem -Filter $Filter -Path $Path | ForEach-Object {
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($_.FullName)
    $target = $shortcut.TargetPath

    if (Test-Path $target) {
      New-Item -ItemType $ItemType -Path "$($_.BaseName)" -Target $target -Force
      Write-Host "Created $ItemType for $($_.Name) -> $target"
    }
    else {
      Write-Host "Target not found for $($_.Name)"
    }
  }

}

################################################################
# # shprofile script aliases
function Connect-TunnelRdp {
  Invoke-ShProfileScript 'Connect-TunnelRdp' @args
}

function Connect-SshLocalPortForward {
  Invoke-ShProfileScript 'Connect-SshLocalPortForward' @args
}

Set-Alias trdp Connect-TunnelRdp
Set-Alias sshl Connect-SshLocalPortForward




################################################################
# # source .shprofile.ps1
function Invoke-ShProfile {
  Write-Host "Current shell: $((Get-Process -Id $PID).Path)"

  . $ShProfilePath
}

# # child scripts
function Test-ShProfileScriptName {
  param (
    [AllowEmptyString()]
    [string]$Name
  )

  return $Name -cmatch '^[A-Za-z0-9][A-Za-z0-9_-]*$'
}

function Test-ShProfileScriptSyntax {
  param (
    [Parameter(Mandatory = $true)]
    [string]$Path
  )

  $tokens = $null
  $parseErrors = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile(
    $Path,
    [ref]$tokens,
    [ref]$parseErrors
  )

  if ($parseErrors.Count -gt 0) {
    $parseErrorMessage = ($parseErrors | ForEach-Object { $_.Message }) -join '; '
    throw $parseErrorMessage
  }
}

function Install-ShProfileScriptItem {
  param (
    [Parameter(Mandatory = $true)]
    [string]$Name
  )

  if (-not (Test-ShProfileScriptName $Name)) {
    Write-Error "Invalid shprofile script name: $Name"
    Write-Error "Script names use letters, numbers, underscores, and hyphens without a .ps1 suffix."
    return $false
  }

  New-Item -ItemType Directory -Path $ShProfileScriptsHome -Force | Out-Null

  $scriptPath = Join-Path $ShProfileScriptsHome "$Name.ps1"
  $scriptNew = Join-Path $ShProfileScriptsHome ".$Name.new.$PID.$([guid]::NewGuid().ToString('N')).ps1"
  $scriptUrl = "$ShProfileRepoRawUrl/.shprofile_scripts/$Name.ps1"

  try {
    Invoke-WebRequest -UseBasicParsing -Uri $scriptUrl -OutFile $scriptNew -ErrorAction Stop
    Test-ShProfileScriptSyntax $scriptNew
    Move-Item -LiteralPath $scriptNew -Destination $scriptPath -Force
    Write-Host "Installed: $Name"
    return $true
  }
  catch {
    Remove-Item -LiteralPath $scriptNew -Force -ErrorAction SilentlyContinue
    Write-Error "Failed to install shprofile script '$Name': $($_.Exception.Message)"
    return $false
  }
}

function Install-AllShProfileScripts {
  New-Item -ItemType Directory -Path $ShProfileScriptsHome -Force | Out-Null

  $manifestNew = Join-Path $ShProfileScriptsHome ".manifest.new.$PID.$([guid]::NewGuid().ToString('N')).txt"
  $failedScripts = @()
  $scriptCount = 0

  try {
    Invoke-WebRequest -UseBasicParsing -Uri $ShProfileScriptsManifestUrl -OutFile $manifestNew -ErrorAction Stop

    foreach ($manifestLine in Get-Content -LiteralPath $manifestNew) {
      $scriptName = $manifestLine.Trim()
      if (-not $scriptName -or $scriptName.StartsWith('#')) {
        continue
      }

      $scriptCount++
      if (-not (Test-ShProfileScriptName $scriptName)) {
        Write-Error "Invalid shprofile script name in manifest: $scriptName"
        $failedScripts += $scriptName
      }
      elseif (-not (Install-ShProfileScriptItem $scriptName)) {
        $failedScripts += $scriptName
      }
    }
  }
  catch {
    Write-Error "Failed to download shprofile script manifest: $($_.Exception.Message)"
    return $false
  }
  finally {
    Remove-Item -LiteralPath $manifestNew -Force -ErrorAction SilentlyContinue
  }

  if ($failedScripts.Count -gt 0) {
    Write-Error "Failed shprofile scripts: $($failedScripts -join ', ')"
    return $false
  }

  if ($scriptCount -eq 0) {
    Write-Host "No shprofile scripts are listed in the manifest."
  }

  return $true
}

function Install-ShProfileScript {
  if ($args.Count -ne 1) {
    Write-Error "Usage: ish <script_name> | ish -a"
    return
  }

  if ($args[0] -eq '-a') {
    [void](Install-AllShProfileScripts)
  }
  else {
    [void](Install-ShProfileScriptItem ([string]$args[0]))
  }
}

function Invoke-ShProfileScript {
  if ($args.Count -eq 0) {
    Write-Error "Usage: rsh <script_name> [args...]"
    return
  }

  $scriptName = [string]$args[0]
  $scriptArgs = @($args | Select-Object -Skip 1)

  if (-not (Test-ShProfileScriptName $scriptName)) {
    Write-Error "Invalid shprofile script name: $scriptName"
    return
  }

  $scriptPath = Join-Path $ShProfileScriptsHome "$scriptName.ps1"
  if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
    Write-Error "shprofile script is not installed: $scriptName"
    Write-Error "Run 'ish $scriptName' first."
    return
  }

  & $scriptPath @scriptArgs
}

# # update .shprofile.ps1
function Update-ShProfile {
  $updateAll = $false

  if ($args.Count -eq 1 -and $args[0] -eq '-a') {
    $updateAll = $true
  }
  elseif ($args.Count -ne 0) {
    Write-Error "Usage: urc [-a]"
    return
  }

  $shProfileNew = Join-Path $HOME ".shprofile.new.$PID.$([guid]::NewGuid().ToString('N')).ps1"
  $url = "$ShProfileRepoRawUrl/.shprofile.ps1"

  try {
    & curl.exe -fSL $url -o $shProfileNew
    if ($LASTEXITCODE -ne 0) {
      throw "curl.exe exited with code $LASTEXITCODE."
    }
    Test-ShProfileScriptSyntax $shProfileNew
    . $shProfileNew
    Move-Item -LiteralPath $shProfileNew -Destination $ShProfilePath -Force
    Write-Host "Updated .shprofile.ps1 successfully."
  }
  catch {
    Remove-Item -LiteralPath $shProfileNew -Force -ErrorAction SilentlyContinue
    Write-Error "Failed to update .shprofile.ps1: $($_.Exception.Message)"
    Invoke-ShProfile
    return
  }

  Invoke-ShProfile

  if ($updateAll) {
    [void](Install-AllShProfileScripts)
  }
}

Set-Alias src Invoke-ShProfile
Set-Alias urc Update-ShProfile
Set-Alias ish Install-ShProfileScript
Set-Alias rsh Invoke-ShProfileScript
################################################################
