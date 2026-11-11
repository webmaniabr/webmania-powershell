param([Parameter(Mandatory)][string]$Archive,[Parameter(Mandatory)][string]$OutputDirectory)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
$prefix=Join-Path /tmp ('alpha6-locale-'+[guid]::NewGuid().ToString('N'));Expand-Archive $Archive $prefix
Import-Module (Join-Path $prefix 'Webmania/Webmania.psd1')
$assembly=[Webmania.WebmaniaClient].Assembly;$resources=[ordered]@{}
foreach($name in ($assembly.GetManifestResourceNames()|Sort-Object)){
 $stream=$assembly.GetManifestResourceStream($name);$m=[IO.MemoryStream]::new()
 try{$stream.CopyTo($m);$resources[$name]=[Convert]::ToHexStringLower([Security.Cryptography.SHA256]::HashData($m.ToArray()))}finally{$stream.Dispose();$m.Dispose()}
}
if(@(Get-WebmaniaOperation).Count -ne 103){throw 'Locale metadata load failed'}
Add-Type -Path (Join-Path $PSScriptRoot 'SocketFixture.cs')
$server=[PsSocketFixture]::new($false)
$options=[Webmania.WebmaniaClientOptions]::new();$options.LoopbackTestEndpoint=[uri]"http://127.0.0.1:$($server.Port)/"
$secure=ConvertTo-SecureString 'alpha6-locale-synthetic' -AsPlainText -Force
$client=New-WebmaniaCompanyClient -ConsumerKey $secure -ConsumerSecret $secure -AccessToken $secure -AccessTokenSecret $secure -Options $options
try{
 $server.Json('{"uuid":"00000000-0000-4000-8000-000000000001","status":"concluido","message":{"city":"São Paulo"}}')
 $parameters=[Webmania.NfeGetDocumentParameters]::new();$parameters.ID=[Webmania.Optional[string]]::Of('locale-positive')
 $response=Get-WebmaniaNfeDocument -Client $client -Parameters $parameters
 $city=$response.Data.AsVariant1().AsVariant1().Extras['message'].GetProperty('city').GetString()
 if($city -cne 'São Paulo' -or $server.Requests.Count -ne 1){throw 'Locale typed UTF8 data load failed'}
}finally{$client.Dispose();$server.Dispose()}
@{status='pass';lang=$env:LANG;lcAll=$env:LC_ALL;culture=[Globalization.CultureInfo]::CurrentCulture.Name;operations=@(Get-WebmaniaOperation).Count;publicTypes=$assembly.GetExportedTypes().Count;typedUtf8City=$city;loopbackHttpRequests=1;resourceSha256=$resources;archiveSha256=(Get-FileHash $Archive).Hash.ToLowerInvariant()}|ConvertTo-Json -Depth 8|Set-Content (Join-Path $OutputDirectory ('locale-'+$env:LANG.Replace('.','_')+'.json'))
Write-Output "PASS: installed contracts under LANG=$env:LANG LC_ALL=$env:LC_ALL"
