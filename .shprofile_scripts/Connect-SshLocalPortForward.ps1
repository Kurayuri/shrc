[CmdletBinding()]
param (
  [Parameter(Mandatory, Position = 0)]
  [ValidateNotNullOrEmpty()]
  [string]$HostName,

  [Parameter(Mandatory, Position = 1)]
  [ValidateRange(1, 65535)]
  [int]$SourcePort,

  [Parameter(Position = 2)]
  [ValidateRange(1, 65535)]
  [int]$DestinationPort = $SourcePort
)

& ssh -L "${SourcePort}:localhost:${DestinationPort}" $HostName
