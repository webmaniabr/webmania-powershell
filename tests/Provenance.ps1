param([Parameter(Mandatory)][string]$Archive,[Parameter(Mandatory)][string]$OutputDirectory)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$prefix=Join-Path /tmp ('alpha6-normal-prefix-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $prefix|Out-Null
Expand-Archive $Archive $prefix
$env:PSModulePath=$prefix+[IO.Path]::PathSeparator+$env:PSModulePath
$members=[Collections.Generic.List[object]]::new();$package=[IO.Compression.ZipFile]::OpenRead($Archive)
try{
 foreach($entry in $package.Entries){
  if($entry.FullName.EndsWith('/')){continue}
  if(-not $entry.FullName.StartsWith('Webmania/') -or $entry.FullName.Contains('..') -or $entry.FullName.Contains('\')){throw 'Unsafe package member origin'}
  $stream=$entry.Open();$memory=[IO.MemoryStream]::new()
  try{$stream.CopyTo($memory);$expected=[Convert]::ToHexStringLower([Security.Cryptography.SHA256]::HashData($memory.ToArray()))}finally{$stream.Dispose();$memory.Dispose()}
  $installed=Join-Path $prefix $entry.FullName
  $source=Join-Path (Join-Path (Split-Path $PSScriptRoot) 'module') $entry.FullName
  if((Get-FileHash $installed).Hash.ToLowerInvariant() -ne $expected -or (Get-FileHash $source).Hash.ToLowerInvariant() -ne $expected){throw 'Package/source/install member mismatch'}
  $members.Add(@{path=$entry.FullName;bytes=$entry.Length;sha256=$expected;sourceCorrespondence=$true;installedFromArchive=$true})
 }
}finally{$package.Dispose()}
$installedFiles=@(Get-ChildItem (Join-Path $prefix Webmania) -Recurse -File)
if($installedFiles.Count -ne $members.Count){throw 'Unexpected installed module members'}
if([AppDomain]::CurrentDomain.GetAssemblies()|Where-Object {$_.GetName().Name -like 'Webmania*'}){throw 'Not a fresh consumer process'}
Import-Module Webmania
$module=Get-Module Webmania
if($module.ModuleBase -ne (Join-Path $prefix Webmania)){throw 'Normal module resolution used another origin'}
$lock=Get-Content (Join-Path $module.ModuleBase dependency.lock.json) -Raw|ConvertFrom-Json
foreach($entry in @(@{type=[Webmania.WebmaniaClient];file='Webmania.Sdk.dll';sha=$lock.assemblySha256},@{type=[Webmania.PowerShell.SafeTypeAttribute];file='Webmania.PowerShell.Runtime.dll';sha=$lock.powerShellRuntimeBridge.assemblySha256})){
 $expected=Join-Path $module.ModuleBase ('bin/'+$entry.file)
 if($entry.type.Assembly.Location -ne $expected -or (Get-FileHash $expected).Hash.ToLowerInvariant() -ne $entry.sha){throw 'Loaded assembly origin/hash mismatch'}
}
$signatures=[Collections.Generic.List[object]]::new();$common=@('Verbose','Debug','ErrorAction','WarningAction','InformationAction','ProgressAction','ErrorVariable','WarningVariable','InformationVariable','OutVariable','OutBuffer','PipelineVariable')
foreach($command in (Get-Command -Module Webmania|Sort-Object Name)){
 $parameters=@(foreach($parameter in ($command.Parameters.Values|Where-Object Name -notin $common|Sort-Object Name)){
  if(-not @($parameter.Attributes|Where-Object {$_ -is [Webmania.PowerShell.SafeTypeAttribute]}).Count){throw 'Unguarded public owned binder'}
  @{name=$parameter.Name;type=$parameter.ParameterType.ToString();guarded=$true;pipeline=@($parameter.ParameterSets.GetEnumerator()|Where-Object {$_.Value.ValueFromPipeline}|ForEach-Object Key)}
 })
 $signatures.Add(@{command=$command.Name;parameters=$parameters;outputTypes=@($command.OutputType|ForEach-Object {$_.Type.ToString()})})
}
$catalog=Get-Content (Join-Path $module.ModuleBase commands.json) -Raw|ConvertFrom-Json
$methodSignatures=@(foreach($entry in $catalog){$method=[Webmania.WebmaniaClient].GetMethod($entry.method);if($null -eq $method -or $method.GetParameters()[0].ParameterType.FullName -ne $entry.parametersType){throw 'Operation signature drift'};@{operationId=$entry.operationId;method=$method.Name;parameters=@($method.GetParameters()|ForEach-Object {$_.ParameterType.ToString()});result=$method.ReturnType.ToString()}})
if($signatures.Count -ne 126 -or $catalog.Count -ne 103){throw 'Unexpected public API cardinality'}
$resourceHashes=[ordered]@{};$assembly=[Webmania.WebmaniaClient].Assembly
foreach($name in ($assembly.GetManifestResourceNames()|Sort-Object)){$stream=$assembly.GetManifestResourceStream($name);$memory=[IO.MemoryStream]::new();try{$stream.CopyTo($memory);$resourceHashes[$name]=[Convert]::ToHexStringLower([Security.Cryptography.SHA256]::HashData($memory.ToArray()))}finally{$stream.Dispose();$memory.Dispose()}}
@{status='pass';archiveSha256=(Get-FileHash $Archive).Hash.ToLowerInvariant();normalImportByName=$true;moduleOrigin=$module.ModuleBase;sdkOrigin=[Webmania.WebmaniaClient].Assembly.Location;bridgeOrigin=[Webmania.PowerShell.SafeTypeAttribute].Assembly.Location;allMemberCount=$members.Count;members=@($members);sourceFreeFunctionalConsumer=$true;publicCommands=$signatures.Count;operationCommands=$catalog.Count;enabled=@(Get-WebmaniaOperation|Where-Object Enabled).Count;blocked=@(Get-WebmaniaOperation|Where-Object {-not $_.Enabled}).Count;schemaModelCount=@($assembly.GetExportedTypes()|Where-Object {[Attribute]::IsDefined($_,[Webmania.SchemaSourceAttribute])}).Count;embeddedResourcesSha256=$resourceHashes;externalApiCalls=0}|ConvertTo-Json -Depth 16|Set-Content (Join-Path $OutputDirectory provenance.json)
@{powerShell=@($signatures);sdkOperations=@($methodSignatures);contractsLockSha256=(Get-FileHash (Join-Path $module.ModuleBase contracts.lock.json)).Hash.ToLowerInvariant()}|ConvertTo-Json -Depth 14|Set-Content (Join-Path $OutputDirectory public-signatures.json)
Write-Output "PASS: all $($members.Count) package members match source and isolated normal prefix;126 guarded public commands/103 exact operation signatures"
