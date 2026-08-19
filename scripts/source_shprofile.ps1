# Usage: . .\scripts\source_shprofile.ps1
# The file must be dot-sourced so its functions and aliases remain in this shell.

if ($MyInvocation.InvocationName -ne '.') {
  Write-Error 'Usage: . .\scripts\source_shprofile.ps1'
  return
}

$_shProfileDevRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $_shProfileDevRoot '.shprofile.ps1')
$ShProfileScriptsHome = Join-Path $_shProfileDevRoot '.shprofile_scripts'

Write-Host "Loaded development shprofile: $_shProfileDevRoot"
Remove-Variable _shProfileDevRoot
