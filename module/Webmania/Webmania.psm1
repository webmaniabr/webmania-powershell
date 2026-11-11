$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if($PSVersionTable.PSVersion -lt [version]'7.6' -or [Environment]::Version.Major -ne 10){throw 'Webmania alpha requires PowerShell 7.6+ on .NET 10. Only Linux ARM64 PS 7.6.8/.NET 10.0.14 is qualified.'}
# Every file is addressed by one literal path object: hashing, loading and dot-sourcing never
# resolve wildcards, so a module root containing [ ] * ? loads exactly the verified bytes.
$moduleRoot=$PSScriptRoot
$dll=[IO.Path]::Combine($moduleRoot,'bin','Webmania.Sdk.dll')
$expected='c7a6f33f12d326ab56a0fd94c692eb93a818c6a8588e1097bfcdf16506e0e2b9'
$bridge=[IO.Path]::Combine($moduleRoot,'bin','Webmania.PowerShell.Runtime.dll')
$expectedBridge='204e9db51e5406ffe243fdd69d741940da28fed1ddc26ebb081326465599c099'
if((Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expected){throw 'Webmania dependency hash mismatch; import stopped.'}
$loaded=@([AppDomain]::CurrentDomain.GetAssemblies()|Where-Object {$_.GetName().Name -eq 'Webmania.Sdk'})
if($loaded -and ($loaded.Count -gt 1 -or -not $loaded.Location -or (Get-FileHash -LiteralPath $loaded.Location).Hash.ToLowerInvariant() -ne $expected)){throw 'A different Webmania.Sdk assembly is already loaded. Start a new PowerShell process.'}
Add-Type -LiteralPath $dll
if((Get-FileHash -LiteralPath $bridge -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expectedBridge){throw 'Webmania PowerShell runtime bridge hash mismatch.'}
$loadedBridge=@([AppDomain]::CurrentDomain.GetAssemblies()|Where-Object {$_.GetName().Name -eq 'Webmania.PowerShell.Runtime'})
if($loadedBridge -and ($loadedBridge.Count -gt 1 -or -not $loadedBridge.Location -or (Get-FileHash -LiteralPath $loadedBridge.Location).Hash.ToLowerInvariant() -ne $expectedBridge)){throw 'A different Webmania PowerShell runtime bridge is already loaded. Start a new PowerShell process.'}
$bridgeAssembly=if($loadedBridge){$loadedBridge[0]}else{[Reflection.Assembly]::LoadFrom($bridge)}
Import-Module -Assembly $bridgeAssembly -Scope Local
foreach($part in @('Core.ps1','Factories.ps1','Operations.ps1','Helpers.ps1')){
    $tokens=$null;$parseErrors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile([IO.Path]::Combine($moduleRoot,$part),[ref]$tokens,[ref]$parseErrors)
    if($parseErrors){throw "Webmania module file $part could not be parsed."}
    . $ast.GetScriptBlock()
}
$commands=@(([IO.File]::ReadAllText([IO.Path]::Combine($moduleRoot,'commands.json'))|ConvertFrom-Json).command)
$commands+=@('New-WebmaniaCompanyClient','New-WebmaniaIssuerClient','New-WebmaniaMonitorClient','New-WebmaniaResellerClient','New-WebmaniaApi1FilesCompanyClient','New-WebmaniaApi1ReportCapabilityClient','New-WebmaniaReportCapabilityClient','New-WebmaniaApi1FilesDocumentTokenClient','New-WebmaniaApi2FilesCompanyBearerClient','New-WebmaniaApi2FilesDocumentTokenClient','New-WebmaniaApi2FilesAnonymousClient','Get-WebmaniaOperation','New-WebmaniaJsonNumber','New-WebmaniaOptional','Wait-WebmaniaFiscalReport','Get-WebmaniaMonitorCompanyItem','Get-WebmaniaMonitorCompanyMunicipalityItem','Get-WebmaniaMonitorReportItem','Save-WebmaniaFile','Wait-WebmaniaMonitorImport','Read-WebmaniaMonitorCompanyBatch','Read-WebmaniaMonitorCompanyMunicipalityBatch','Read-WebmaniaMonitorReportBatch')
Export-ModuleMember -Function $commands -Cmdlet @()
