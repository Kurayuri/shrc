################################################################
# # Windows PowerShell Run Commands
################################################################

################################################################
# # Env
$ProfileHome = "C:\Windows\System32\WindowsPowerShell\v1.0"
$ProfilePath = "C:\Windows\System32\WindowsPowerShell\v1.0\Profile.ps1"

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
# # source .shrc
function Invoke-Profile {
  Write-Host "Current shell: $((Get-Process -Id $PID).Path)"
  
  . $ProfilePath
}

# # update .shrc
function Update-Profile {
  $newProfilePath = "$ProfileHome\Profile_.ps1"
  $url = "https://gitee.com/kurayuri/shrc/raw/main/Profile.ps1"

  try {
    Invoke-WebRequest -Uri $url -OutFile $newProfilePath

    try {
      . $newProfilePath
      Remove-Item $ProfilePath
      Rename-Item -Path $newProfilePath -NewName $ProfilePath
      Write-Host "Updated Profile.ps1 successfully."
    }
    catch {
      Write-Host "Error loading new Profile.ps1."
      Remove-Item $newProfilePath
    }
  }
  catch {
    Write-Host "Failed to download new Profile.ps1."
    Remove-Item $newProfilePath -ErrorAction SilentlyContinue
  }

  Invoke-Profile
}

Set-Alias src Invoke-Profile
Set-Alias urc Update-Profile
################################################################



