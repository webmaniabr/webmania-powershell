param([Parameter(Mandatory)][string]$OutputDirectory)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot
New-Item -ItemType Directory -Force $OutputDirectory|Out-Null
$compiler='/usr/share/dotnet/sdk/10.0.403/Roslyn/bincore/csc.dll'
$reference='/usr/share/dotnet/packs/Microsoft.NETCore.App.Ref/10.0.14/ref/net10.0'
$argsList=@($compiler,'/nologo','/target:library','/deterministic+','/optimize+','/nullable:enable','/langversion:latest',('/out:'+(Join-Path $OutputDirectory 'Webmania.PowerShell.Runtime.dll')))
$argsList+=@(Get-ChildItem "$reference/*.dll"|ForEach-Object {'/reference:'+ $_.FullName})
$argsList+='/reference:'+ (Join-Path $PSHOME 'System.Management.Automation.dll')
$argsList+='/reference:'+ (Join-Path $root 'module/Webmania/bin/Webmania.Sdk.dll')
$argsList+=Join-Path $root 'runtime/InvocationRuntime.cs'
& dotnet @argsList
if($LASTEXITCODE -ne 0){throw 'Runtime bridge compilation failed'}
Get-FileHash (Join-Path $OutputDirectory 'Webmania.PowerShell.Runtime.dll')
