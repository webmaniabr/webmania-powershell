function UpdateInput([string]$Reference='PS-ALPHA6-SAFE-REFERENCE'){
 [Text.Json.JsonSerializer]::Deserialize(('{"body":{"cnae":null,"uuid":"'+$Reference+'"}}'),[Webmania.FiscalUpdateCompanyParameters],[Webmania.WebmaniaJson]::Options)
}
function CompanySecrets($Server,[string[]]$Values){$v=@($Values|ForEach-Object {ConvertTo-SecureString $_ -AsPlainText -Force})
New-WebmaniaCompanyClient -ConsumerKey $v[0] -ConsumerSecret $v[1] -AccessToken $v[2] -AccessTokenSecret $v[3] -Options (Options $Server)}
Probe @('REDACT-01') 'three overlapping credentials protected as union in both insertion orders' {
 foreach($values in @(@('ABCDEF','DEFGHI','GHIJKL','alpha6-fourth'),@('GHIJKL','DEFGHI','ABCDEF','alpha6-fourth'))){$s=[DeltaRawServer]::new()
$c=CompanySecrets $s $values
try{$s.Json('{"error":"ABCDEFGHIJKL public sentence"}',422)
$e=Failure {Set-WebmaniaFiscalCompany -Client $c -Parameters (UpdateInput)} 'http'
Check ((Diagnostic $e).Message -eq '[redacted] public sentence') 'entire overlap union'
Check ($s.Count -eq 1) 'no replay'}finally{Capture $s
$c.Dispose()
$s.Dispose()}}
@{orders=2
unionProtected=$true}
}
Probe @('REDACT-02') 'configured x and1234 remain literal substring secrets; original extra-word oracle conflicts explicitly' {
 foreach($pair in @(@('x','extra x (x)'),@('1234','912345 1234'))){$s=[DeltaRawServer]::new()
$c=CompanySecrets $s @($pair[0],'other-secret','other-access','other-access-secret')
try{$s.Json((@{error=$pair[1]+' public sentence'}|ConvertTo-Json -Compress),422)
$e=Failure {Set-WebmaniaFiscalCompany -Client $c -Parameters (UpdateInput)} 'http'
$text=(Diagnostic $e).Message
Check (-not $text.Contains($pair[0]) -and $text.Contains('public sentence')) 'configured credential substring policy unchanged'}finally{Capture $s
$c.Dispose()
$s.Dispose()}}
@{configuredLiteralSubstring=$true
originalCatalogOracle='FAIL-POLICY-CONFLICT: configured x removes x in extra; retained, never weakened'
original49PassClaim=$false}
}
Probe @('REDACT-02','REDACT-03') 'only observed short capabilities use boundaries and preserve structural/public vocabulary' {
 foreach($pair in @(@('x','extra x (x)'),@('ABA','ABABA ABA (ABA)'),@('12','912345 12 (12)'))){$s=[DeltaRawServer]::new()
$c=Company $s
try{$s.Json((@{error=$pair[1]+' public sentence'}|ConvertTo-Json -Compress),422,"Location: /export?ticket=$($pair[0])`r`n")
$e=Failure {Set-WebmaniaFiscalCompany -Client $c -Parameters (UpdateInput)} 'http'
Check ((Diagnostic $e).Message.StartsWith($pair[1].Split(' ')[0]+' [redacted] ([redacted])')) 'observed short boundary'
Check ((Diagnostic $e).Message.Contains('public sentence')) 'useful public words'}finally{Capture $s
$c.Dispose()
$s.Dispose()}}
@{observedBoundaryControls=3}
}
Probe @('ERR-02','REDACT-03','REDACT-06') 'actual typed serialized snapshot protects extension key/value while preserving structure' {
 $s=[DeltaRawServer]::new()
$c=Company $s
 try{
  $p=[Text.Json.JsonSerializer]::Deserialize('{"body":{"cnae":null,"enabled":false,"extra_data":{"visible_field":true,"private_token_key":"PRIVATE-VALUE-987","0":{"nested":"PRIVATE-NUMERIC-KEY-456"},"list":["PRIVATE-LIST-123"]}}}',[Webmania.FiscalUpdateCompanyParameters],[Webmania.WebmaniaJson]::Options)
  $s.Json('{"error":{"message":"body cnae enabled false null true visible_field private_token_key PRIVATE-VALUE-987 PRIVATE-NUMERIC-KEY-456 PRIVATE-LIST-123 public sentence","field":"cnae","code":75}}',422)
$e=Failure {Set-WebmaniaFiscalCompany -Client $c -Parameters $p} 'http'
$text=PublicText $e
  foreach($private in @('private_token_key','PRIVATE-VALUE-987','PRIVATE-NUMERIC-KEY-456','PRIVATE-LIST-123')){Check (-not $text.Contains($private)) 'snapshot private value absent'}
Check ((Diagnostic $e).Message.Contains('body cnae enabled false null true visible_field')) 'structural vocabulary survives'
$actual=[Text.Json.JsonDocument]::Parse(@($s.Requests)[0].Body)
try{Check ($actual.RootElement.GetProperty('extra_data').GetProperty('0').ValueKind -eq [Text.Json.JsonValueKind]::Object) 'numeric property name remains object'
Check ($actual.RootElement.GetProperty('extra_data').GetProperty('list').ValueKind -eq [Text.Json.JsonValueKind]::Array) 'list shape remains array'}finally{$actual.Dispose()}
@{requests=$s.Count
privateValuesProtected=4
shapesPreserved=$true}
 }finally{Capture $s
$c.Dispose()
$s.Dispose()}
}
Probe @('ERR-04') 'protected sent mutation selector deliberately recovers with exact serialized value' {
 $s=[DeltaRawServer]::new()
$c=Company $s
 try{$reference='1a2b3c4d-1234-4234-8234-1234567890ab'
$s.Json((@{error=$reference+' rejected'}|ConvertTo-Json -Compress),503)
$e=Failure {Set-WebmaniaFiscalCompany -Client $c -Parameters (UpdateInput $reference)} 'http'
$d=Diagnostic $e
Check ($d.OutcomeUncertain -and $d.SafeReference.CanReveal -and -not(PublicText $e).Contains($reference)) 'protected uncertain recovery'
$s.Json('{"uuid":"00000000-0000-4000-8000-000000000001","status":"concluido"}')
$null=Get-WebmaniaNfeDocument -Client $c -Parameters ($d.SafeReference.ToLookupParameters())
Check ($s.Count -eq 2 -and @($s.Requests)[1].Target.Contains($reference)) 'one explicit consultation uses retained selector'
@{requests=$s.Count
mutationReplays=0
deliberateLookup=$true}}finally{Capture $s
$c.Dispose()
$s.Dispose()}
}
Probe @('REDIR-01') 'documented file redirect stays protected metadata with no fetch and invalid controls reject' {
 $s=[DeltaRawServer]::new()
$c=New-WebmaniaApi2FilesCompanyBearerClient -Bearer $secret -Options (Options $s)
$p=Input 'fileGetNfsePdf'
 try{
  foreach($location in @('https://untrusted.example.test/private/12345678-1234-4234-8234-1234567890ab?ticket=opaque-token','/export?ticket=relative-token')){$s.Reply([byte[]]::new(0),'text/plain',302,"Location: $location`r`n")
$r=Get-WebmaniaFileNfsePdf -Client $c -Parameters $p
Check (-not $r.IsFile -and $r.RedirectLocation.Reveal() -eq $location) 'protected location deliberate access'
Check (-not $r.ToString().Contains('ticket=')) 'ordinary file text no URL'}
  foreach($headers in @('',"Location: https://[broken/private`r`n","Location: /one`r`nLocation: /two`r`n")){$s.Reply([byte[]]::new(0),'text/plain',302,$headers)
$null=Failure {Get-WebmaniaFileNfsePdf -Client $c -Parameters $p}}
Check ($s.Count -eq 5) 'no destination fetch or replay'
@{requests=$s.Count
followed=0
positive=2
invalid=3}
 }finally{Capture $s
$c.Dispose()
$s.Dispose()}
}
Probe @('ERR-03','REDIR-03','REDACT-04','REDACT-05','ERR-06') 'observed Location capabilities across informational, final, encoded, fragment and malformed boundaries' {
 $cap='A1B2C3D4-1234-4234-8234-ABCDEF012345'
$s=[DeltaRawServer]::new()
$c=Company $s
 try{
  foreach($location in @("/private/prefix-$cap.pdf","/x?ticket%3D$cap","/x#key=$cap","/x;key=$cap","https://[broken/x?key=$cap")){$echo=if($location.StartsWith('/private/')){$cap.ToLowerInvariant()}else{$cap}
$s.Json((@{error=$echo+' public sentence'}|ConvertTo-Json -Compress),503,"Location: $location`r`nX-Request-ID: $echo`r`n")
$e=Failure {Set-WebmaniaFiscalCompany -Client $c -Parameters (UpdateInput $echo)}
Check (-not(PublicText $e).Contains($echo) -and (Diagnostic $e).SafeReference.CanReveal -ne $true) 'equivalent observed capability protected and collision withheld'}
  foreach($code in @(100,103,101)){$body='{"error":"'+$cap.ToLowerInvariant()+' public sentence"}'
$s.Enqueue("HTTP/1.1 $code Info`r`nLocation: /private/$cap`r`n`r`nHTTP/1.1 503 Error`r`nContent-Type: application/json`r`nContent-Length: $([Text.Encoding]::UTF8.GetByteCount($body))`r`nConnection: close`r`nX-Request-ID: $($cap.ToLowerInvariant())`r`n`r`n$body")
$e=Failure {Set-WebmaniaFiscalCompany -Client $c -Parameters (UpdateInput $cap.ToLowerInvariant())}
Check (-not(PublicText $e).Contains($cap.ToLowerInvariant())) 'informational capability observed before rejection'}
  @{requests=$s.Count
locations=8
followed=0}
 }finally{Capture $s
$c.Dispose()
$s.Dispose()}
}
Probe @('POLL-01','POLL-03') 'bounded report snapshot protects capabilities across case and preserves Unicode response text' {
 $s=[DeltaRawServer]::new()
$c=Company $s
$p=Input 'fiscalCreateOrPollReport'
$poll=[Webmania.PollOptions]::new()
$poll.MaximumAttempts=2
$poll.Deadline=[timespan]::FromSeconds(8)
$cap='A1B2C3D4-1234-4234-8234-ABCDEF012345'
 try{
  $s.Json('{"uuid":"'+$cap+'","status":"processando","url":"https://files.example.test/ação?token=report-private-token"}')
$s.Json('{"error":"'+$cap.ToLowerInvariant()+' report-private-token"}',503)
$watch=[Diagnostics.Stopwatch]::StartNew()
$e=Failure {Wait-WebmaniaFiscalReport -Client $c -Parameters $p -Options $poll} 'http'
Check ($watch.Elapsed.TotalSeconds -ge 5 -and $s.Count -eq 2) 'minimum5sec no retry'
Check (@($s.Requests)[0].Body -ceq @($s.Requests)[1].Body) 'same frozen payload'
Check (-not(PublicText $e).Contains($cap.ToLowerInvariant()) -and -not(PublicText $e).Contains('report-private-token')) 'workflow report capabilities private'
  $s.Json('{"uuid":"'+$cap+'","status":"concluido","url":"https://files.example.test/ação?token=report-private-token"}')
$r=Wait-WebmaniaFiscalReport -Client $c -Parameters $p
Check ($r.Json.GetProperty('url').GetString().Contains('ação') -and $s.Count -eq 3) 'Unicode response preserved without download'
@{requests=$s.Count
minimumInterval=5
unicodePreserved=$true}
 }finally{Capture $s
$c.Dispose()
$s.Dispose()}
}
Probe @('FILE-03','FILE-04') 'stored ZIP local-central mismatches duplicate names and real CRC payload corruption fail closed' {
 $s=[PsSocketFixture]::new($false)
$c=New-WebmaniaApi1ReportCapabilityClient -Options (Options $s)
$p=Input 'fiscalDownloadReport'
$base=[DeltaArchives]::Stored([string[]]@('one.txt','two.txt'))
$central=[DeltaArchives]::Signature($base,0x02014b50)
$s.Media='application/zip'
 try{
  $s.Body=$base
$r=Receive-WebmaniaFiscalReport -Client $c -Parameters $p
Check ($r.IsFile) 'disjoint archive positive'
  foreach($offset in @(6,8,14,22)){$s.Body=[DeltaArchives]::Change($base,$offset,[byte]($base[$offset] -bxor 1))
$null=Failure {Receive-WebmaniaFiscalReport -Client $c -Parameters $p} 'protocol'}
  $data=30+[BitConverter]::ToUInt16($base,26)+[BitConverter]::ToUInt16($base,28)
$s.Body=[DeltaArchives]::Change($base,$data,[byte]($base[$data] -bxor 1))
$null=Failure {Receive-WebmaniaFiscalReport -Client $c -Parameters $p} 'protocol'
  $duplicate=[DeltaArchives]::Stored([string[]]@('same.txt','same.txt'))
$s.Body=$duplicate
$r=$null
$e=$null
try{$r=Receive-WebmaniaFiscalReport -Client $c -Parameters $p}catch{$e=$_}
Check ($null -ne $e -or -not $r.IsFile) 'duplicate member names nonready'
  $overlap=[byte[]]$base.Clone()
$second=[DeltaArchives]::Signature($base,0x02014b50,$central+4)
[Array]::Copy([byte[]]@(0,0,0,0),0,$overlap,$second+42,4)
$s.Body=$overlap
$null=Failure {Receive-WebmaniaFiscalReport -Client $c -Parameters $p} 'protocol'
@{requests=$s.Requests.Count
positive=1
rejected=7}
 }finally{Capture $s
$c.Dispose()
$s.Dispose()}
}
Probe @('FILE-05') 'XML prolog comments and1024attributes stay usable; duplicates and DTD reject without entity fetch' {
 $s=[PsSocketFixture]::new($false)
$c=New-WebmaniaApi1FilesCompanyClient -ConsumerKey $secret -ConsumerSecret $secret -AccessToken $secret -AccessTokenSecret $secret -Options (Options $s)
$p=Input 'nfeDownloadXml'
$s.Media='application/xml'
 try{
  foreach($count in @(16,1024)){$attrs=(1..$count|ForEach-Object {' a'+$_+'="v"'}) -join ''
$s.Body=[Text.Encoding]::UTF8.GetBytes('<?xml version="1.0"?><!--safe--><root'+$attrs+'/>')
$watch=[Diagnostics.Stopwatch]::StartNew()
$r=Receive-WebmaniaNfeXml -Client $c -Parameters $p
Check ($r.IsFile -and $watch.ElapsedMilliseconds -lt 1500) 'bounded XML attributes and bytes usable'}
  $entity=[DeltaRawServer]::new()
  try{
   foreach($xml in @('<root a="1" a="2"/>',"<!DOCTYPE root SYSTEM `"http://127.0.0.1:$($entity.Port)/entity`"><root/>")){$s.Body=[Text.Encoding]::UTF8.GetBytes($xml)
$null=Failure {Receive-WebmaniaNfeXml -Client $c -Parameters $p} 'protocol'}
   Check ($s.Requests.Count -eq 4 -and $entity.Count -eq 0 -and $entity.Accepts -eq 0) 'no entity fetch or replay'
   @{requests=$s.Requests.Count
maximumAttributes=1024
externalEntityFetches=$entity.Accepts}
  }finally{$entity.Dispose()}
 }finally{Capture $s
$c.Dispose()
$s.Dispose()}
}
Probe @('LIMIT-01','LIMIT-02') 'accepted nested response remains accessible and overlimit caller extension rejects beforeHTTP' {
 $s=[DeltaRawServer]::new()
$c=Company $s
 try{
  $nested='"leaf"'
foreach($n in 1..60){$nested='{"n":'+$nested+'}'}
$s.Json('{"expiration":1,"extra":'+$nested+'}')
$r=Cert $c
$typed=$r.Data.AsVariant1()
$text=[Text.Json.JsonSerializer]::Serialize($typed,[Webmania.WebmaniaJson]::Options)
Check ($text.Contains('leaf') -and $typed.Extras['extra'].ValueKind -eq [Text.Json.JsonValueKind]::Object) 'accepted nested projection/serialization'
  $deep='"private-deep"'
foreach($n in 1..300){$deep='{"n":'+$deep+'}'}
$p=UpdateInput
$opts=[Text.Json.JsonDocumentOptions]::new()
$opts.MaxDepth=512
$doc=[Text.Json.JsonDocument]::Parse($deep,$opts)
try{$before=$s.Count
$e=Failure {$p.Body.Value.Extras.Add('extra',$doc.RootElement)
Set-WebmaniaFiscalCompany -Client $c -Parameters $p}
Check ($s.Count -eq $before -and -not(PublicText $e).Contains('private-deep')) 'callerdepth300 safe zeroHTTP'}finally{$doc.Dispose()}
$s.Json('{"expiration":1}')
$null=Cert $c
@{acceptedDepth=60
rejectedCallerDepth=300
survived=$true
requests=$s.Count}
 }finally{Capture $s
$c.Dispose()
$s.Dispose()}
}
Probe @('TYPE-05') 'original UUID-constrained selector rejects surrogate beforeHTTP and preserves valid UUID' {
 $s=[PsSocketFixture]::new($false)
 $issuer=New-WebmaniaApi2FilesCompanyBearerClient -Bearer $secret -Options (Options $s)
 try{
  $p=[Webmania.FileGetNfsePdfParameters]::new()
  $p.Identifier=[Webmania.Optional[string]]::Of([string][char]0xD800)
  $null=Failure {Get-WebmaniaFileNfsePdf -Client $issuer -Parameters $p} 'validation'
  Check ($s.Requests.Count -eq 0) 'invalid surrogate zeroHTTP original constrained selector'
  $p.Identifier=[Webmania.Optional[string]]::Of('00000000-0000-4000-8000-000000000001')
  $s.File('application/pdf')
  $null=Get-WebmaniaFileNfsePdf -Client $issuer -Parameters $p
  Check ($s.Requests.Count -eq 1) 'valid UUID positive'
  @{surrogateRejected=$true;validUuidRequests=1;scope='original UUID schema; free-string selector additional control separate'}
 }finally{Capture $s;$issuer.Dispose();$s.Dispose()}
}
Probe @('TYPE-05') 'additional unconstrained selector must reject isolated surrogate without lossy dispatch' {
 $s=[DeltaRawServer]::new()
 $issuer=New-WebmaniaIssuerClient -Bearer $secret -Options (Options $s)
 try{
  $p=[Webmania.EmitterGetDceParameters]::new()
  $p.Identifier=[Webmania.Optional[string]]::Of([string][char]0xD800)
  $s.Json('{"uuid":"synthetic","status":"concluido"}')
  $e=$null
  try{Get-WebmaniaEmitterDce -Client $issuer -Parameters $p|Out-Null}catch{$e=$_}
  Check ($null -ne $e -and $s.Count -eq 0) 'unconstrained surrogate rejected beforeHTTP'
  @{requests=$s.Count;lossyDispatch=$false}
 }finally{Capture $s;$issuer.Dispose();$s.Dispose()}
}
Probe @('ENV-02') 'malformed IPv6 origins fail without additionalHTTP' {
 $s=[DeltaRawServer]::new()
 try{
  foreach($origin in @('https://[1.2.3.4::]/','https://[1::2::3]/','https://[12345::]/','https://[::ffff:999.1.1.1]/','https://[::1]:99999/')){
   $rejected=$false
   try{$bad=[Webmania.WebmaniaClientOptions]::new();$bad.ServiceEndpoint=[uri]$origin;$b=New-WebmaniaMonitorClient -Bearer $secret -Options $bad;$b.Dispose()}catch{$rejected=$true}
   Check $rejected 'malformed IPv6 or port rejected'
  }
  Check ($s.Count -eq 0) 'malformed origin zeroHTTP'
  @{requests=0;malformedOrigins=5;ipv6SocketAvailability='not claimed'}
 }finally{Capture $s;$s.Dispose()}
}
Probe @('ENV-01','TLS-01','TLS-02') 'installed HTTPS trust/name positives and explicit trustedCNfallback observation' {
 $details=[Collections.Generic.List[object]]::new()
 foreach($cnOnly in @($false,$true)){$s=[PsSocketFixture]::new($true,$cnOnly)
$o=[Webmania.WebmaniaClientOptions]::new()
$o.ServiceEndpoint=[uri]"https://localhost:$($s.Port)/approved/"
$o.LoopbackTestRootCertificate=[Security.Cryptography.X509Certificates.X509CertificateLoader]::LoadCertificate($s.CertificateDer)
$c=New-WebmaniaCompanyClient -ConsumerKey $secret -ConsumerSecret $secret -AccessToken $secret -AccessTokenSecret $secret -Options $o
 try{$s.Json('{"expiration":1}')
$null=Cert $c
Check ($s.Requests.Count -eq 1 -and @($s.Requests)[0].Target.StartsWith('/approved/')) 'configured HTTPS prefix'
$details.Add(@{cnOnly=$cnOnly
requests=$s.Requests.Count
trusted=$true
strictSanQualified=(-not $cnOnly)})}finally{Capture $s
$c.Dispose()
$s.Dispose()}}
 foreach($origin in @('https://user:pass@localhost/','https://localhost/?query=x','https://localhost/#part','https://localhost/a/../b/')){$o=[Webmania.WebmaniaClientOptions]::new()
$o.ServiceEndpoint=[uri]$origin
$null=Failure {New-WebmaniaMonitorClient -Bearer $secret -Options $o} 'LocalValidation'}
 @{details=@($details)
strictSAN='BLOCKED: runtime trusted CN fallback, intentionally documented'
anonymousNullPositiveControl='NOT_TESTED: no positively negotiated isolated anonymous/NULL server in this PS harness'}
}
Probe @('CANCEL-01','CANCEL-04') 'sameClient queued caller cancellation is native, zero additionalHTTP, sent sibling retains uncertainty' {
 $s=[IndependentServer]::new()
$o=[Webmania.WebmaniaClientOptions]::new()
$o.LoopbackTestEndpoint=$s.Url
$c=New-WebmaniaCompanyClient -ConsumerKey $secret -ConsumerSecret $secret -AccessToken $secret -AccessTokenSecret $secret -Options $o
$firstCancel=[Threading.CancellationTokenSource]::new()
$queuedCancel=[Threading.CancellationTokenSource]::new()
 try{$s.Enqueue([IndependentReply]@{Hold=$true})
$first=Set-WebmaniaFiscalCompany -Client $c -Parameters (UpdateInput 'PS-QUEUED-SAFE-REF') -CancellationToken $firstCancel.Token -AsTask
Check ($s.WaitCount(1,2000)) 'sent first mutation'
$queued=Get-WebmaniaNfeCertificateValidity -Client $c -Parameters ([Webmania.NfeGetCertificateValidityParameters]::new()) -CancellationToken $queuedCancel.Token -AsTask
[Threading.Thread]::Sleep(50)
$queuedCancel.Cancel()
$e=Failure {$queued.GetAwaiter().GetResult()}
$d=Diagnostic $e
Check ($queued.IsCanceled -and $null -ne $d -and -not $d.OutcomeUncertain -and $s.Count -eq 1) 'queued caller canceled before dispatch'
$firstCancel.Cancel()
$e=Failure {$first.GetAwaiter().GetResult()}
$d=Diagnostic $e
Check ($first.IsCanceled -and $d.OutcomeUncertain -and $d.SafeReference.Reveal() -eq 'PS-QUEUED-SAFE-REF' -and -not(PublicText $e).Contains('PS-QUEUED-SAFE-REF')) 'sent sibling metadata private'
$s.Enqueue([IndependentReply]@{Body='{"expiration":1}'})
$null=Cert $c
Check ($s.Count -eq 2) 'fresh sibling unaffected'
@{queuedHTTP=0
sentHTTP=1
freshHTTP=1}}
 finally{$c.Dispose()
$firstCancel.Dispose()
$queuedCancel.Dispose()
Capture $s
$s.Dispose()}
}
Probe @('CANCEL-04') 'batch preCanceled helper stays nativeTask and synchronous cancellation never becomes LocalValidation' {
 $s=[DeltaRawServer]::new()
$c=Monitor $s
$cts=[Threading.CancellationTokenSource]::new()
$cts.Cancel()
 try{$p=[Webmania.MonitorListCompaniesParameters]::new()
$task=Read-WebmaniaMonitorCompanyBatch -Client $c -Parameters $p -MaximumItems 1 -CancellationToken $cts.Token -AsTask
$e=Failure {$task.GetAwaiter().GetResult()}
Check ($task.IsCanceled) 'native batch canceledTask'
$e=Failure {Read-WebmaniaMonitorCompanyBatch -Client $c -Parameters $p -MaximumItems 1 -CancellationToken $cts.Token} 'cancelled'
Check ($e.Exception.OperationId -eq 'monitorListCompanies' -and -not $e.Exception.OutcomeUncertain -and $s.Count -eq 0) 'safe earlyhelper cancellation context'
@{requests=0
nativeTaskCanceled=$true
ordinaryKind='cancelled'
earlyHelperSdkDiagnostic='not created by SDK; fixed safe bridge diagnostic'}}finally{Capture $s
$c.Dispose()
$cts.Dispose()
$s.Dispose()}
}

Probe @('REDACT-07') 'bounded observed capability family keeps diagnostic work and output finite with noLocation control' {
 $measurements=[Collections.Generic.List[object]]::new()
 foreach($count in @(0,16,128)){
  $s=[DeltaRawServer]::new()
  $c=Company $s
  try{
   $tokens=@(1..([Math]::Max(1,$count))|ForEach-Object {'CAP-ALPHA6-'+$_.ToString('D4')})
   $headers=if($count){'Location: /export?'+(($tokens|ForEach-Object {'k='+$_}) -join '&')+"`r`n"}else{''}
   $body=@{error=($tokens -join ' ')+' public sentence'}|ConvertTo-Json -Compress
   $s.Json($body,422,$headers)
   $watch=[Diagnostics.Stopwatch]::StartNew()
   $e=Failure {Set-WebmaniaFiscalCompany -Client $c -Parameters (UpdateInput)} 'http'
   $text=(Diagnostic $e).Message
   Check ($watch.ElapsedMilliseconds -lt 1500 -and $text.Length -lt 32768 -and $s.Count -eq 1) 'work/output/noReplay bounds'
   if($count){foreach($token in $tokens){Check (-not $text.Contains($token)) 'all bounded family tokens protected'}}
   $measurements.Add(@{capabilities=$count;elapsedMs=$watch.ElapsedMilliseconds;messageLength=$text.Length;requests=1})
  }finally{Capture $s;$c.Dispose();$s.Dispose()}
 }
 @{measurements=@($measurements);scope='bounded family, no asymptotic universal claim'}
}
Probe @('LIMIT-02') 'childProcess rejects4096deep caller value and exits normally withoutHTTP' {
 $s=[DeltaRawServer]::new()
 try{
  $output=& pwsh -NoLogo -NoProfile -NonInteractive -File (Join-Path $PSScriptRoot 'DepthChild.ps1') -Manifest $manifest -Port $s.Port
  Check ($LASTEXITCODE -eq 0 -and $s.Count -eq 0) 'isolated child survived with zeroHTTP'
  $receipt=$output|ConvertFrom-Json
  Check ($receipt.status -eq 'pass' -and $receipt.depth -eq 4096) 'depth child own receipt'
  @{child=$receipt;requests=0;exitCode=$LASTEXITCODE}
 }finally{Capture $s;$s.Dispose()}
}

Probe @('PAGE-01','PAGE-02') 'municipality and report batches retain exact typed continuations and native typedTask' {
 $s=[DeltaRawServer]::new()
 $c=Monitor $s
 try{
  $municipality=[Webmania.MonitorListCompanyMunicipalitiesParameters]::new()
  $municipality.Company=[Webmania.Optional[string]]::Of('00000000-0000-4000-8000-000000000001')
  $item='{"uuid":"00000000-0000-4000-8000-000000000001","tipo_download":1,"municipio":"Synthetic","uf":"SP","codigo_ibge":"3550308"}'
  $s.Json('{"data":['+$item+','+$item+'],"meta":{"current_page":1,"last_page":1,"per_page":10,"total":2}}')
  $first=Read-WebmaniaMonitorCompanyMunicipalityBatch -Client $c -Parameters $municipality -MaximumItems 1
  Check ($first.Items[0] -is [Webmania.Api2MonitorReadsMonitorMunicipalityRegistration] -and $first.Continuation -is [Webmania.MonitorContinuation[Webmania.Api2MonitorReadsMonitorMunicipalityRegistration]]) 'exact municipality types'
  $last=Read-WebmaniaMonitorCompanyMunicipalityBatch -Client $c -Parameters $municipality -MaximumItems 1 -Continuation $first.Continuation
  Check ($last.Items.Count -eq 1 -and $null -eq $last.Continuation -and $s.Count -eq 1) 'municipality buffered end noHTTP'
  $item='{"uuid":"00000000-0000-4000-8000-000000000002","relatorio":"xml","modelo":"nfe","status":"concluido"}'
  $s.Json('{"data":['+$item+'],"meta":{"current_page":1,"last_page":1,"per_page":10,"total":1}}')
  $task=Read-WebmaniaMonitorReportBatch -Client $c -Parameters ([Webmania.MonitorListReportsParameters]::new()) -MaximumItems 1 -AsTask
  Check ($task -is [Threading.Tasks.Task[Webmania.MonitorBatch[Webmania.Api2MonitorDocumentsMonitorReport]]]) 'genuine typed report batchTask'
  $result=$task.GetAwaiter().GetResult()
  Check ($result.Items.Count -eq 1 -and $result.Items[0] -is [Webmania.Api2MonitorDocumentsMonitorReport] -and $s.Count -eq 2) 'typed report result'
  @{requests=$s.Count;municipalityContinuation=$true;nativeReportTask=$true}
 }finally{Capture $s;$c.Dispose();$s.Dispose()}
}
Probe @('POLL-02') 'import wait freezes original UUID across minimum5sec interval and bounds sleeping deadline' {
 $s=[DeltaRawServer]::new()
 $c=Monitor $s
 try{
  $p=Input 'monitorGetImportStatus'
  $body=@{uuid='00000000-0000-4000-8000-000000000001';status='processando';processado=0;importados=@();descartados=@()}
  $s.Json(($body|ConvertTo-Json -Compress))
  $body.status='concluido'
  $s.Json(($body|ConvertTo-Json -Compress))
  $poll=[Webmania.PollOptions]::new();$poll.MaximumAttempts=2;$poll.Deadline=[timespan]::FromSeconds(8)
  $watch=[Diagnostics.Stopwatch]::StartNew()
  $task=Wait-WebmaniaMonitorImport -Client $c -Parameters $p -Options $poll -AsTask
  while($s.Count -lt 1 -and $watch.ElapsedMilliseconds -lt 1500){[Threading.Thread]::Sleep(5)}
  $p.Uuid=[Webmania.Optional[string]]::Of('00000000-0000-4000-8000-000000000099')
  $result=$task.GetAwaiter().GetResult()
  Check ($result.Data.Status.Value -eq 'concluido' -and $watch.Elapsed.TotalSeconds -ge 5 -and $s.Count -eq 2) 'bounded typed polling interval'
  Check (@($s.Requests)[0].Target -ceq @($s.Requests)[1].Target) 'original UUID frozen across caller mutation'
  $body.status='processando';$s.Json(($body|ConvertTo-Json -Compress));$poll.Deadline=[timespan]::FromMilliseconds(250);$poll.MaximumAttempts=5
  $watch.Restart()
  $null=Failure {Wait-WebmaniaMonitorImport -Client $c -Parameters $p -Options $poll} 'timeout'
  Check ($watch.ElapsedMilliseconds -lt 1000 -and $s.Count -eq 3) 'deadline while sleeping no additionalHTTP'
  @{requests=3;minimumInterval=5;deadlineRequests=1;originalSnapshot=$true}
 }finally{Capture $s;$c.Dispose();$s.Dispose()}
}

Probe @('ENV-01') 'untrusted chain and trusted wrongSAN hostname refuse before applicationHTTP with approved sibling positive' {
 $details=[Collections.Generic.List[object]]::new()
 foreach($wrongName in @($false,$true)){
  $s=[PsSocketFixture]::new($true,$false,$wrongName)
  $o=[Webmania.WebmaniaClientOptions]::new()
  $o.ServiceEndpoint=[uri]"https://localhost:$($s.Port)/"
  if($wrongName){$o.LoopbackTestRootCertificate=[Security.Cryptography.X509Certificates.X509CertificateLoader]::LoadCertificate($s.CertificateDer)}
  $c=New-WebmaniaCompanyClient -ConsumerKey $secret -ConsumerSecret $secret -AccessToken $secret -AccessTokenSecret $secret -Options $o
  try{
   $s.Json('{"expiration":1}')
   $null=Failure {Cert $c} 'transport'
   Check ($s.Requests.Count -eq 0) 'untrusted/wrongName no applicationHTTP'
   $details.Add(@{wrongName=$wrongName;httpRequests=0;rejected=$true})
  }finally{Capture $s;$c.Dispose();$s.Dispose()}
 }
 @{details=@($details);approvedSibling='SAN HTTPS positive in installed environment case'}
}
Probe @('ENV-02') 'actual IPv6 loopback availability and typed HTTP consumer' {
 $s=[DeltaRawServer]::new($true)
 $o=[Webmania.WebmaniaClientOptions]::new()
 $o.LoopbackTestEndpoint=[uri]"http://[::1]:$($s.Port)/"
 $c=New-WebmaniaCompanyClient -ConsumerKey $secret -ConsumerSecret $secret -AccessToken $secret -AccessTokenSecret $secret -Options $o
 try{
  $s.Json('{"expiration":1}')
  $null=Cert $c
  Check ($s.Count -eq 1) 'IPv6 typed consumer positive'
  @{ipv6Available=$true;httpRequests=1;origin='[::1]'}
 }finally{Capture $s;$c.Dispose();$s.Dispose()}
}

Probe @('FILE-01') 'declared opaque report remains unsupported and cannot be saved as a ready file' {
 $s=[PsSocketFixture]::new($false)
 $c=New-WebmaniaMonitorClient -Bearer $secret -Options (Options $s)
 try{
  $p=Input 'monitorDownloadReport'
  $s.Media='application/octet-stream'
  $s.Body=[byte[]]@(1,2,3,4)
  $result=Receive-WebmaniaMonitorReport -Client $c -Parameters $p
  Check ($result.Representation -eq [Webmania.FileRepresentation]::Other -and $result.Readiness -eq [Webmania.FileReadiness]::Unsupported -and -not $result.IsFile) 'opaque is an explicit unsupported representation'
  Check ([Convert]::ToHexString($result.Bytes.ToArray()) -eq '01020304') 'opaque caller-visible bytes preserved'
  $path=Join-Path $OutputDirectory 'opaque-refused.bin'
  $null=Failure {$result|Save-WebmaniaFile -LiteralPath $path} 'LocalValidation'
  Check (-not(Test-Path $path) -and $s.Requests.Count -eq 1) 'opaque refusal no write or extra request'
  @{requests=1;representation='Other';readiness='Unsupported';saved=$false}
 }finally{Capture $s;$c.Dispose();$s.Dispose()}
}
Probe @('ERR-05','CANCEL-02') 'effectful file operation transport failure beforeHTTP remains certain and never retries' {
 $s=[DeltaRawServer]::new()
 $port=$s.Port
 $s.Dispose()
 $options=[Webmania.WebmaniaClientOptions]::new()
 $options.LoopbackTestEndpoint=[uri]"http://127.0.0.1:$port/"
 $options.Timeout=[timespan]::FromMilliseconds(500)
 $c=New-WebmaniaApi2FilesCompanyBearerClient -Bearer $secret -Options $options
 try{
  $p=Input 'fileGetNfsePdf'
  $e=Failure {Get-WebmaniaFileNfsePdf -Client $c -Parameters $p} 'transport'
  Check (-not $e.Exception.OutcomeUncertain -and $e.Exception.OperationId -eq 'fileGetNfsePdf' -and $null -eq $e.Exception.StatusCode) 'preHTTP file context certain'
  Check ($s.Count -eq 0 -and $s.Accepts -eq 0) 'closed listener no HTTP or TCP acceptance'
  @{httpRequests=0;tcpAccepts=0;kind='transport';outcomeUncertain=$false}
 }finally{$c.Dispose()}
}
