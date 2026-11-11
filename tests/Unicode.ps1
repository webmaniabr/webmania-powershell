param([Parameter(Mandatory)][string]$Archive,[Parameter(Mandatory)][string]$OutputDirectory)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$install=Join-Path /tmp ('ps5-unicode-'+[guid]::NewGuid().ToString('N'))
Expand-Archive $Archive $install
Import-Module (Join-Path $install 'Webmania/Webmania.psd1')
Add-Type -Path (Join-Path $PSScriptRoot 'DeltaFixture.cs')
Add-Type -Path (Join-Path $PSScriptRoot 'SocketFixture.cs')
Add-Type -Path (Join-Path $PSScriptRoot 'UnicodeFixture.cs')
$results=[Collections.Generic.List[object]]::new()
$wire=[Collections.Generic.List[object]]::new()
$script:assertions=0
$marker='PS5-'+'UNICODE-CANARY'
$good=[string][char]0xFFFD+[char]::ConvertFromUtf32(0x1F642)
$secret=ConvertTo-SecureString 'ps5-synthetic-credential' -AsPlainText -Force
function Check([bool]$Ok,[string]$Name){$script:assertions++;if(-not $Ok){throw "Unicode assertion failed: $Name"}}
function Probe([string]$Name,[scriptblock]$Action){
 $start=$script:assertions
 try{$actual=&$Action;$results.Add(@{scenario=$Name;status='pass';assertions=$script:assertions-$start;actual=$actual})}
 catch{$results.Add(@{scenario=$Name;status='fail';assertions=$script:assertions-$start;error=$_.ToString();stack=$_.ScriptStackTrace});Write-Output "FAIL: $Name - $_"}
}
function SafeFailure([scriptblock]$Action,[string]$Kind=''){
 $caught=$null
 try{&$Action|Out-Null}catch{$caught=$_}
 Check ($null -ne $caught) 'rejected'
 if($Kind){Check ($caught.FullyQualifiedErrorId -like "Webmania.$Kind,*") 'structured protected kind'}
 $text=$caught.ToString()+$caught.Exception.ToString()+($caught|Format-List * -Force|Out-String -Width 4096)+($caught.InvocationInfo|Format-List * -Force|Out-String -Width 4096)
 Check (-not $text.Contains($marker)) 'public error and InvocationInfo omit caller marker'
 Check ($null -eq $caught.TargetObject) 'error target is null'
 return $caught
}
function Options($Server){$o=[Webmania.WebmaniaClientOptions]::new();$o.LoopbackTestEndpoint=[uri]"http://127.0.0.1:$($Server.Port)/";return $o}
function Company($Server){New-WebmaniaCompanyClient -ConsumerKey $secret -ConsumerSecret $secret -AccessToken $secret -AccessTokenSecret $secret -Options (Options $Server)}
function Update($Body){$p=[Webmania.FiscalUpdateCompanyParameters]::new();$p.Body=[Webmania.Optional[Webmania.Api1FiscalFiscalCompanyUpdateRequest]]::Of($Body);return $p}
function Element($Value){$method=[Webmania.WebmaniaJson].GetMethod('ToElement').MakeGenericMethod($Value.GetType());$method.Invoke($null,[object[]]@(,$Value))}
function Capture($Server){$scheme=if($Server -is [PsSocketFixture] -and $Server.IsTls){'https'}else{'http'};foreach($r in $Server.Requests){$wire.Add(@{scheme=$scheme;method=$r.Method;target=$r.Target;headers=$r.Headers;body=$r.Body})}}
Probe 'high and low surrogates reject in free path, query, native body and extension key before TCP' {
 $s=[DeltaRawServer]::new()
 $issuer=New-WebmaniaIssuerClient -Bearer $secret -Options (Options $s)
 $monitor=New-WebmaniaMonitorClient -Bearer $secret -Options (Options $s)
 $company=Company $s
 try{
  foreach($unit in @(0xD800,0xDC00)){
   $invalid=$marker+[char]$unit
   $p=[Webmania.EmitterGetDceParameters]::new()
   $p.Identifier=[Webmania.Optional[string]]::Of($invalid)
   $e=SafeFailure {Get-WebmaniaEmitterDce -Client $issuer -Parameters $p} 'validation'
   Check ($e.Exception.OperationId -eq 'emitterGetDce' -and -not $e.Exception.OutcomeUncertain -and $null -eq $e.Exception.StatusCode -and $null -eq $e.Exception.InnerException) 'free path diagnostic precise'
   $p=[Webmania.MonitorListCompaniesParameters]::new()
   $p.Pesquisa=[Webmania.Optional[string]]::Of($invalid)
   $e=SafeFailure {Get-WebmaniaMonitorCompanies -Client $monitor -Parameters $p} 'validation'
   $body=[Webmania.Api1FiscalFiscalCompanyUpdateRequest]::new()
   $body.NomeFantasia=[Webmania.Optional[string]]::Of($invalid)
   $p=Update $body
   $e=SafeFailure {Set-WebmaniaFiscalCompany -Client $company -Parameters $p} 'validation'
   $body=[Webmania.Api1FiscalFiscalCompanyUpdateRequest]::new()
   $body.Extras.Add($invalid,[Text.Json.JsonDocument]::Parse('1').RootElement.Clone())
   $p=Update $body
   $e=SafeFailure {Set-WebmaniaFiscalCompany -Client $company -Parameters $p} 'validation'
  }
  [Threading.Thread]::Sleep(30)
  Check ($s.Count -eq 0 -and $s.Accepts -eq 0) 'all invalid typed values zero HTTP and TCP'
  @{surrogateUnits=2;typedBoundaries=4;httpRequests=$s.Count;tcpAccepts=$s.Accepts}
 }finally{Capture $s;$issuer.Dispose();$monitor.Dispose();$company.Dispose();$s.Dispose()}
}
Probe 'valid replacement character astral text and ordinary text stay exact through path query body and extension keys' {
 $s=[DeltaRawServer]::new()
 $issuer=New-WebmaniaIssuerClient -Bearer $secret -Options (Options $s)
 $monitor=New-WebmaniaMonitorClient -Bearer $secret -Options (Options $s)
 $company=Company $s
 try{
  foreach($value in @(('v-'+$good),'ordinary-exact')){
   $s.Json('{"uuid":"synthetic","status":"concluido"}')
   $p=[Webmania.EmitterGetDceParameters]::new()
   $p.Identifier=[Webmania.Optional[string]]::Of($value)
   $null=Get-WebmaniaEmitterDce -Client $issuer -Parameters $p
   Check ([uri]::UnescapeDataString(@($s.Requests)[-1].Target).EndsWith('/'+$value)) 'path text exact'
   $s.Json('{"data":[],"meta":{"current_page":1,"last_page":1,"per_page":50,"total":0}}')
   $p=[Webmania.MonitorListCompaniesParameters]::new()
   $p.Pesquisa=[Webmania.Optional[string]]::Of($value)
   $null=Get-WebmaniaMonitorCompanies -Client $monitor -Parameters $p
   Check ([uri]::UnescapeDataString(@($s.Requests)[-1].Target).Contains('pesquisa='+$value)) 'query text exact'
   $s.Json('{"success":"ok"}')
   $body=[Webmania.Api1FiscalFiscalCompanyUpdateRequest]::new()
   $body.NomeFantasia=[Webmania.Optional[string]]::Of($value)
   $body.Extras.Add('key-'+$value,[Text.Json.JsonDocument]::Parse('true').RootElement.Clone())
   $p=Update $body
   $null=Set-WebmaniaFiscalCompany -Client $company -Parameters $p
   $doc=[Text.Json.JsonDocument]::Parse(@($s.Requests)[-1].Body)
   try{Check ($doc.RootElement.GetProperty('nome_fantasia').GetString() -ceq $value -and $doc.RootElement.GetProperty('key-'+$value).GetBoolean()) 'body value and key exact'}finally{$doc.Dispose()}
  }
  Check ($s.Count -eq 6) 'one request per explicit positive command'
  @{httpRequests=$s.Count;validUFFFD=$true;validAstral=$true;ordinaryPreserved=$true}
 }finally{Capture $s;$issuer.Dispose();$monitor.Dispose();$company.Dispose();$s.Dispose()}
}
Probe 'raw escaped invalid JSON rejects and valid raw Unicode plus exact response number remains usable' {
 $s=[DeltaRawServer]::new()
 $company=Company $s
 try{
  foreach($escape in @('\uD800','\uDC00')){
   $doc=[Text.Json.JsonDocument]::Parse('"'+$escape+'"')
   try{
    $body=[Webmania.Api1FiscalFiscalCompanyUpdateRequest]::new()
    $body.Extras.Add('raw',$doc.RootElement)
    $p=Update $body
    $null=SafeFailure {Set-WebmaniaFiscalCompany -Client $company -Parameters $p} 'validation'
   }finally{$doc.Dispose()}
  }
  Check ($s.Count -eq 0 -and $s.Accepts -eq 0) 'invalid raw JSON zero TCP'
  $body=[Webmania.Api1FiscalFiscalCompanyUpdateRequest]::new()
  $doc=[Text.Json.JsonDocument]::Parse('"\uFFFD\uD83D\uDE42"')
  try{$body.Extras.Add('raw',$doc.RootElement);$p=Update $body;$s.Json('{"success":"ok"}');$null=Set-WebmaniaFiscalCompany -Client $company -Parameters $p}finally{$doc.Dispose()}
  $sent=[Text.Json.JsonDocument]::Parse(@($s.Requests)[-1].Body)
  try{Check ($sent.RootElement.GetProperty('raw').GetString() -ceq $good) 'valid raw caller Unicode exact'}finally{$sent.Dispose()}
  $s.Json('{"expiration":1,"extra":"\uD800"}')
  $p=[Webmania.NfeGetCertificateValidityParameters]::new()
  $e=SafeFailure {Get-WebmaniaNfeCertificateValidity -Client $company -Parameters $p} 'protocol'
  Check ($e.Exception.StatusCode -eq 200 -and $null -eq $e.Exception.InnerException) 'malformed response diagnostic safe'
  $s.Json('{"expiration":1.0,"extra":"\uFFFD\uD83D\uDE42"}')
  $r=Get-WebmaniaNfeCertificateValidity -Client $company -Parameters $p
  $typed=$r.Data.AsVariant1()
  Check ($typed.Expiration.Value.Text -ceq '1.0' -and $typed.Extras['extra'].GetString() -ceq $good) 'valid response Unicode and exact number preserved'
  @{httpRequests=$s.Count;invalidCallerTCP=0;malformedResponse='protocol';validRawPreserved=$true}
 }finally{Capture $s;$company.Dispose();$s.Dispose()}
}
Probe 'ordinary public JSON helper snapshots each getter and custom converter once' {
 $counted=[UnicodeCountedValue]::new()
 $element=Element $counted
 Check ($counted.Reads -eq 1 -and $element.GetProperty('Text').GetString() -ceq ('valid-'+$good.Substring(0,1)+'-'+$good.Substring(1))) 'getter exactly once'
 $converted=[UnicodeConvertedValue]::new()
 $element=Element $converted
 Check ($converted.Writes -eq 1 -and $element.GetProperty('text').GetString() -ceq $converted.Text) 'converter exactly once'
 @{getterReads=$counted.Reads;converterWrites=$converted.Writes;surface='imported public WebmaniaJson.ToElement, not a PowerShell DTO generator'}
}
Probe 'invalid credential and retained Uri OriginalString fail with safe local factory errors while valid Unicode origin stays usable' {
 $s=[PsSocketFixture]::new($true)
 $root=[Security.Cryptography.X509Certificates.X509CertificateLoader]::LoadCertificate($s.CertificateDer)
 try{
  foreach($unit in @(0xD800,0xDC00)){
   $invalid=$marker+[char]$unit
   $badSecret=ConvertTo-SecureString $invalid -AsPlainText -Force
   $null=SafeFailure {New-WebmaniaIssuerClient -Bearer $badSecret} 'LocalValidation'
   $o=[Webmania.WebmaniaClientOptions]::new()
   $o.ServiceEndpoint=[uri]("https://localhost:$($s.Port)/"+$invalid+'/')
   Check ($o.ServiceEndpoint.OriginalString.Contains([char]$unit)) 'Uri retains invalid original unit'
   $o.LoopbackTestRootCertificate=$root
   $null=SafeFailure {New-WebmaniaIssuerClient -Bearer $secret -Options $o} 'LocalValidation'
  }
  Check ($s.Requests.Count -eq 0) 'invalid factories no HTTP'
  $o=[Webmania.WebmaniaClientOptions]::new()
  $o.ServiceEndpoint=[uri]("https://localhost:$($s.Port)/valid-"+$good+'/')
  $o.LoopbackTestRootCertificate=$root
  $c=New-WebmaniaCompanyClient -ConsumerKey $secret -ConsumerSecret $secret -AccessToken $secret -AccessTokenSecret $secret -Options $o
  try{$s.Json('{"expiration":1}');$null=Get-WebmaniaNfeCertificateValidity -Client $c -Parameters ([Webmania.NfeGetCertificateValidityParameters]::new());Check ([uri]::UnescapeDataString(@($s.Requests)[0].Target).StartsWith('/valid-'+$good+'/')) 'valid Unicode HTTPS origin prefix preserved'}finally{$c.Dispose()}
  @{invalidCredentialCases=2;invalidOriginalStringCases=2;httpsRequests=$s.Requests.Count;validOriginPreserved=$true}
 }finally{Capture $s;$s.Dispose()}
}
$failed=@($results|Where-Object status -eq 'fail')
@{status=$(if($failed.Count){'fail'}else{'pass'});archiveSha256=(Get-FileHash $Archive).Hash.ToLowerInvariant();assertions=$script:assertions;observations=@($results);failed=$failed.Count;capturedApplicationRequests=$wire.Count;httpRequests=@($wire|Where-Object scheme -eq 'http').Count;httpsRequests=@($wire|Where-Object scheme -eq 'https').Count;externalApiCalls=0;attribution='New ordinary public PowerShell UTF16/JSON/helper consumers; wire fixtures compile only as local peers, never replace SDK transport'}|ConvertTo-Json -Depth 16|Set-Content (Join-Path $OutputDirectory unicode-results.json)
ConvertTo-Json -InputObject @($wire) -Depth 12|Set-Content (Join-Path $OutputDirectory unicode-wire.json)
Write-Output "Unicode: $($results.Count) observations; $script:assertions assertions; $($failed.Count) failures; $($wire.Count) captured application requests"
if($failed.Count){throw 'PowerShell Unicode controls contain failures; receipts retained.'}
