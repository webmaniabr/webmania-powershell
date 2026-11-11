param([Parameter(Mandatory)][string]$Archive,[Parameter(Mandatory)][string]$OutputDirectory,[ValidateSet('dependency','bridge','sdk-conflict','bridge-conflict','wildcard-root')][string]$Case='dependency')
$ErrorActionPreference='Stop'
if($Case -eq 'wildcard-root'){
    # Install under a root whose name is a wildcard pattern next to a tampered decoy that the
    # pattern matches. Once PowerShell runs the literal Webmania.psm1, every file the module loads
    # itself (DLLs, script parts, command catalog) comes from the literal root: the decoy is never read.
    # (Importing through Webmania.psd1 is not used here: PowerShell 7.6 resolves a manifest RootModule
    # under such a root as a wildcard, which is outside the module's own loading code.)
    $parent=Join-Path '/tmp' ('ps-wildcard-'+[guid]::NewGuid().ToString('N'))
    $literal=[IO.Path]::Combine($parent,'w[ab]*?');$decoy=[IO.Path]::Combine($parent,'wbx')
    foreach($target in @($literal,$decoy)){[void][IO.Directory]::CreateDirectory($target);[IO.Compression.ZipFile]::ExtractToDirectory($Archive,$target)}
    if(-not [WildcardPattern]::new('w[ab]*?').IsMatch('wbx')){throw 'Decoy is not matched by the wildcard root'}
    foreach($name in @('Webmania.psm1','Core.ps1','Factories.ps1','Operations.ps1','Helpers.ps1')){[IO.File]::WriteAllText([IO.Path]::Combine($decoy,'Webmania',$name),"throw 'decoy module file loaded'")}
    [IO.File]::WriteAllText([IO.Path]::Combine($decoy,'Webmania','commands.json'),'decoy')
    foreach($name in @('Webmania.Sdk.dll','Webmania.PowerShell.Runtime.dll')){$stream=[IO.File]::Open([IO.Path]::Combine($decoy,'Webmania','bin',$name),[IO.FileMode]::Append);try{$stream.WriteByte(0)}finally{$stream.Dispose()}}
    $base=[IO.Path]::Combine($literal,'Webmania')
    Import-Module ([WildcardPattern]::Escape([IO.Path]::Combine($base,'Webmania.psm1')))
    $module=Get-Module Webmania
    if([Webmania.WebmaniaClient].Assembly.Location -ne [IO.Path]::Combine($base,'bin','Webmania.Sdk.dll')){throw 'SDK assembly loaded from another path'}
    if([Webmania.PowerShell.SafeTypeAttribute].Assembly.Location -ne [IO.Path]::Combine($base,'bin','Webmania.PowerShell.Runtime.dll')){throw 'Runtime bridge loaded from another path'}
    if(@(Get-WebmaniaOperation).Count -ne 103 -or $module.ExportedCommands.Count -ne 126){throw 'Module commands incomplete from the wildcard root'}
    @{status='pass';case=$Case;literalRoot=$true;decoyLoaded=$false;externalApiCalls=0}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $OutputDirectory ('import-guard-'+$Case+'.json'))
    Write-Output "PASS: $Case imported only the literal module files"
    return
}
$install=Join-Path '/tmp' ('ps-tamper-'+[guid]::NewGuid().ToString('N'))
Expand-Archive $Archive $install
$member=if($Case -in @('dependency','sdk-conflict')){'Webmania.Sdk.dll'}else{'Webmania.PowerShell.Runtime.dll'}
$dll=Join-Path $install ('Webmania/bin/'+$member)
if($Case -in @('dependency','bridge')){
    $stream=[IO.File]::Open($dll,[IO.FileMode]::Append)
    try{$stream.WriteByte(0)}finally{$stream.Dispose()}
}else{
    $fake=Join-Path /tmp ('conflict-'+[guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory $fake|Out-Null
    $fakeAssembly=Join-Path $fake $member
    $fakeSource=Join-Path $fake 'Conflicting.cs'
    'public sealed class ConflictingWebmaniaAssemblyMarker { }'|Set-Content $fakeSource
    $compilerArguments=@('/usr/share/dotnet/sdk/10.0.403/Roslyn/bincore/csc.dll','/nologo','/target:library','/deterministic+',('/out:'+$fakeAssembly))
    $compilerArguments+=@(Get-ChildItem '/usr/share/dotnet/packs/Microsoft.NETCore.App.Ref/10.0.14/ref/net10.0/*.dll'|ForEach-Object {'/reference:'+ $_.FullName})
    $compilerArguments+=$fakeSource
    & dotnet @compilerArguments
    if($LASTEXITCODE -ne 0){throw 'Conflict fixture compilation failed'}
    Add-Type -Path $fakeAssembly
    if(-not([AppDomain]::CurrentDomain.GetAssemblies()|Where-Object {$_.GetName().Name -eq [IO.Path]::GetFileNameWithoutExtension($member)})){throw 'Conflict fixture did not load expected assembly identity'}
}
$caught=$null
try{Import-Module (Join-Path $install 'Webmania/Webmania.psd1')}catch{$caught=$_}
$expected=switch($Case){'dependency'{'dependency hash mismatch'};'bridge'{'runtime bridge hash mismatch'};'sdk-conflict'{'different Webmania.Sdk assembly'};'bridge-conflict'{'different Webmania PowerShell runtime bridge'}}
if($null -eq $caught -or -not $caught.ToString().Contains($expected)){throw 'Tampered/conflicting assembly was not rejected by import guard'}
if($Case -eq 'dependency' -and ([AppDomain]::CurrentDomain.GetAssemblies()|Where-Object {$_.GetName().Name -eq 'Webmania.Sdk'})){throw 'Tampered SDK was loaded before rejection'}
if($Case -eq 'bridge' -and ([AppDomain]::CurrentDomain.GetAssemblies()|Where-Object {$_.GetName().Name -eq 'Webmania.PowerShell.Runtime'})){throw 'Tampered bridge was loaded before rejection'}
@{status='pass';case=$Case;guardMessage=$expected;externalApiCalls=0}|ConvertTo-Json|Set-Content (Join-Path $OutputDirectory ('import-guard-'+$Case+'.json'))
Write-Output "PASS: $Case rejected in a fresh process"
