param([Parameter(Mandatory)][string]$Archive,[Parameter(Mandatory)][string]$OutputDirectory)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$install=Join-Path /tmp ('alpha6-delta-'+[guid]::NewGuid().ToString('N'))
Expand-Archive $Archive $install
$manifest=Join-Path $install 'Webmania/Webmania.psd1'
Import-Module $manifest
Add-Type -Path (Join-Path $PSScriptRoot 'SocketFixture.cs')
Add-Type -Path (Join-Path $PSScriptRoot 'DeltaFixture.cs')
Add-Type -Path (Join-Path $PSScriptRoot 'LifecycleFixture.cs')
$observations=[Collections.Generic.List[object]]::new()
$wire=[Collections.Generic.List[object]]::new()
$script:assertions=0
function Check([bool]$Ok,[string]$Name){$script:assertions++
if(-not $Ok){throw "Delta assertion failed: $Name"}}
function Probe([string[]]$Ids,[string]$Name,[scriptblock]$Action){
 $watch=[Diagnostics.Stopwatch]::StartNew()
$start=$script:assertions
 try{$actual=&$Action
$observations.Add(@{ids=$Ids
scenario=$Name
status='pass'
assertions=$script:assertions-$start
elapsedMs=$watch.ElapsedMilliseconds
actual=$actual})}
 catch{$observations.Add(@{ids=$Ids
scenario=$Name
status='fail'
assertions=$script:assertions-$start
elapsedMs=$watch.ElapsedMilliseconds
error=$_.ToString()
stack=$_.ScriptStackTrace})
Write-Output "FAIL: $Name - $_"}
}
function Failure([scriptblock]$Action,[string]$Kind=''){
 $caught=$null
try{&$Action|Out-Null}catch{$caught=$_}
Check ($null -ne $caught) 'error expected'
 if($Kind){Check ($caught.FullyQualifiedErrorId -like "Webmania.$Kind,*") "protected $Kind error"}
return $caught
}
function Diagnostic($Caught){$e=$Caught.Exception
while($null -ne $e){if($e -is [Webmania.WebmaniaException]){return $e}
if($e -is [Webmania.WebmaniaCancellationException]){return $e.Diagnostic}
$e=$e.InnerException}
return $null}
function PublicText($Caught){$d=Diagnostic $Caught
return $Caught.ToString()+$Caught.Exception.ToString()+($Caught|Out-String)+($Caught.InvocationInfo|Format-List * -Force|Out-String)+$(if($null -ne $d){[Text.Json.JsonSerializer]::Serialize($d,[Webmania.WebmaniaException],[Webmania.WebmaniaJson]::Options)})}
$secret=ConvertTo-SecureString 'alpha6-synthetic-credential' -AsPlainText -Force
function Options($Server){$o=[Webmania.WebmaniaClientOptions]::new()
$o.LoopbackTestEndpoint=[uri]"http://127.0.0.1:$($Server.Port)/"
$o.Timeout=[timespan]::FromSeconds(3)
return $o}
function Company($Server){New-WebmaniaCompanyClient -ConsumerKey $secret -ConsumerSecret $secret -AccessToken $secret -AccessTokenSecret $secret -Options (Options $Server)}
function Monitor($Server){New-WebmaniaMonitorClient -Bearer $secret -Options (Options $Server)}
function Capture($Server){
 $scheme=if($Server -is [PsSocketFixture] -and $Server.IsTls){'https'}elseif($Server -is [IndependentServer]){([uri]$Server.Url).Scheme}else{'http'}
 foreach($r in $Server.Requests){$wire.Add(@{scheme=$scheme;method=$r.Method;target=$r.Target;headers=$r.Headers;body=$r.Body})}
}
function Cert($Client){Get-WebmaniaNfeCertificateValidity -Client $Client -Parameters ([Webmania.NfeGetCertificateValidityParameters]::new())}
$fixtures=Get-Content (Join-Path $PSScriptRoot 'fixtures/fixtures.json') -Raw|ConvertFrom-Json -AsHashtable
$catalog=Get-Content (Join-Path $install 'Webmania/commands.json') -Raw|ConvertFrom-Json
function Input([string]$Id){$f=@($fixtures|Where-Object id -eq $Id)[0]
$c=@($catalog|Where-Object operationId -eq $Id)[0]
[Text.Json.JsonSerializer]::Deserialize(($f.input|ConvertTo-Json -Depth 96 -Compress),[type]$c.parametersType,[Webmania.WebmaniaJson]::Options)}
function InvokeOp([string]$Id,$Client,$Parameters){$c=@($catalog|Where-Object operationId -eq $Id)[0]
&$c.command -Client $Client -Parameters $Parameters}
Probe @('ENV-03') 'installed metadata and exact assembly/embedded helper origin' {
 Check ([Webmania.WebmaniaClient].Assembly.Location -eq (Join-Path $install 'Webmania/bin/Webmania.Sdk.dll')) 'source-free SDK origin'
 Check ([Webmania.PowerShell.SafeTypeAttribute].Assembly.Location -eq (Join-Path $install 'Webmania/bin/Webmania.PowerShell.Runtime.dll')) 'source-free bridge origin'
 $resource=[Webmania.WebmaniaClient].Assembly.GetManifestResourceStream('Webmania.Dns.Webmania.DnsHelper.dll')
$m=[IO.MemoryStream]::new()
try{$resource.CopyTo($m)
$helper=[Convert]::ToHexStringLower([Security.Cryptography.SHA256]::HashData($m.ToArray()))}finally{$resource.Dispose()
$m.Dispose()}
 Check ($helper -eq '31b286af51dc7eb086f0e76725b209c9f707de94e37d113384f205f582eda23a') 'embedded accepted helper'
 @{operations=@(Get-WebmaniaOperation).Count
helperSha256=$helper
runtimeDirectory=[Runtime.InteropServices.RuntimeEnvironment]::GetRuntimeDirectory()}
}
Probe @('HTTP-01','HTTP-02','HTTP-04') 'complete framing, informational/trailer controls, malformed rejection and fresh reuse' {
 $s=[DeltaRawServer]::new()
$c=Company $s
$valid=0
$invalid=0
 try{
  $body='{"expiration":1}'
$chunkLength=([Text.Encoding]::UTF8.GetByteCount($body)).ToString('x')
  foreach($raw in @("HTTP/1.0 200 OK`r`nContent-Type: application/json`r`n`r`n$body","HTTP/1.1 200 OK`r`nContent-Type: application/json`r`nConnection: close`r`n`r`n$body","HTTP/1.1 100 Continue`r`n`r`nHTTP/1.1 103 Early Hints`r`nLink: </a>`r`n`r`nHTTP/1.1 200 OK`r`nContent-Type: application/json`r`nTransfer-Encoding: chunked`r`nConnection: close`r`n`r`n$chunkLength`r`n$body`r`n0`r`nX-Public: trailer`r`n`r`n")){$s.Enqueue($raw)
$null=Cert $c
$valid++}
  foreach($raw in @("HTTP/1.1 200 OK`r`nContent-Type: application/json`r`nContent-Length: 50`r`nConnection: close`r`n`r`n$body","HTTP/1.1 200 OK`r`nContent-Type: application/json`r`nTransfer-Encoding: chunked`r`n`r`n$chunkLength`r`n$body`r`n0`r`n","HTTP/1.1 200 OK`r`nContent-Type: application/json`r`nContent-Length: 14`r`nTransfer-Encoding: chunked`r`n`r`n0`r`n`r`n","HTTP/1.1 101 Switching Protocols`r`nConnection: upgrade`r`nUpgrade: other`r`n`r`n")){$s.Enqueue($raw)
$null=Failure {Cert $c}
$invalid++}
  $s.Json($body)
$null=Cert $c
Check ($s.Count -eq $valid+$invalid+1) 'one request per call with fresh reuse'
  @{valid=$valid
invalid=$invalid
requests=$s.Count}
 }finally{Capture $s
$c.Dispose()
$s.Dispose()}
}
Probe @('HTTP-03','REDIR-02','ERR-05') 'no replay on fresh accepted GET POST PUT DELETE and sent redirect effect context' {
 $s=[DeltaRawServer]::new()
$company=Company $s
$monitor=Monitor $s
 try{
  $ids=@('nfeGetCertificateValidity','fiscalUpdateCompany','monitorUpdateCompany','monitorDeleteCompanyMunicipality')
  foreach($id in $ids){$entry=@($catalog|Where-Object operationId -eq $id)
Check ($entry.Count -eq 1) 'declared noReplay operation exists'
$client=if($entry[0].scope -eq 'company'){$company}else{$monitor}
$s.Enqueue('')
$before=$s.Count
$e=Failure {InvokeOp $id $client (Input $id)}
Check ($s.Count -eq $before+1) "one accepted request for $id"
Check ((Diagnostic $e).OutcomeUncertain -eq ($id -ne 'nfeGetCertificateValidity')) 'effect context after lost response'}
  foreach($passive in @($false,$true)){$s.Json('{}',302,"Location: http://127.0.0.1:9/never`r`n")
$before=$s.Count
$e=if($passive){Failure {Cert $company} 'redirect'}else{Failure {InvokeOp 'fiscalUpdateCompany' $company (Input 'fiscalUpdateCompany')} 'redirect'}
Check ((Diagnostic $e).OutcomeUncertain -eq (-not $passive)) 'redirect sent effect'
Check ($s.Count -eq $before+1) 'no redirect follow'}
  @{requests=$s.Count
methods=@($s.Requests|ForEach-Object Method)}
 }finally{Capture $s
$company.Dispose()
$monitor.Dispose()
$s.Dispose()}
}
Probe @('ERR-01') 'error discriminator property presence across false null zero and empty values' {
 $s=[DeltaRawServer]::new()
$c=Company $s
 try{foreach($value in @('false','null','0','""','[]','{}')){$s.Json('{"expiration":1,"error":'+$value+'}')
$null=Failure {Cert $c} 'business'}
$s.Json('{"expiration":1}')
$null=Cert $c
Check ($s.Count -eq 7) 'presence errors without replay'
@{requests=$s.Count}}finally{Capture $s
$c.Dispose()
$s.Dispose()}
}
Probe @('PAGE-01','PAGE-02') '75 of 80 exact items, private buffered continuation, filter/page binding and coherent resume' {
 $s=[DeltaRawServer]::new()
$c=Monitor $s
 try{
  $rows=@(1..80|ForEach-Object {@{uuid=('00000000-0000-4000-8000-'+$_.ToString('D12'))}})
  foreach($page in 1..2){$data=if($page -eq 1){$rows[0..49]}else{$rows[50..79]}
$s.Json((@{data=@($data)
meta=@{current_page=$page
last_page=2
per_page=50
total=80}}|ConvertTo-Json -Depth 8 -Compress))}
  $p=[Webmania.MonitorListCompaniesParameters]::new()
$p.PerPage=[Webmania.Optional[Webmania.JsonNumber]]::Of([Webmania.JsonNumber]::new('50'))
  $b=Read-WebmaniaMonitorCompanyBatch -Client $c -Parameters $p -MaximumItems 75
  Check ($b.Items.Count -eq 75 -and @($b.Items.Uuid.Value|Sort-Object -Unique).Count -eq 75) 'exact75 distinct typed records'
Check ($s.Count -eq 2 -and $b.Continuation.Page.Text -eq '2' -and $b.Continuation.ItemIndex -eq 25) 'page2 index25 no page3'
  foreach($request in $s.Requests){Check ($request.Target.Contains('per_page=50')) 'per_page remains50'}
  $public=$b.Continuation.ToString()+[Text.Json.JsonSerializer]::Serialize($b.Continuation,$b.Continuation.GetType(),[Webmania.WebmaniaJson]::Options)
Check (-not $public.Contains($rows[75].uuid)) 'continuation retains no public row data'
  $changed=[Webmania.MonitorListCompaniesParameters]::new()
$changed.PerPage=[Webmania.Optional[Webmania.JsonNumber]]::Of([Webmania.JsonNumber]::new('10'))
$before=$s.Count
$null=Failure {Read-WebmaniaMonitorCompanyBatch -Client $c -Parameters $changed -MaximumItems 5 -Continuation $b.Continuation} 'validation'
Check ($s.Count -eq $before) 'changed snapshot zeroHTTP'
  $end=Read-WebmaniaMonitorCompanyBatch -Client $c -Parameters $p -MaximumItems 5 -Continuation $b.Continuation
Check ($end.Items.Count -eq 5 -and $null -eq $end.Continuation -and $s.Count -eq 2) 'buffered resume5 without HTTP or repeats'
  $huge=[Webmania.MonitorListCompaniesParameters]::new()
$huge.Page=[Webmania.Optional[Webmania.JsonNumber]]::Of([Webmania.JsonNumber]::new('2147483649'))
$s.Json('{"data":[],"meta":{"current_page":2147483649,"last_page":2147483648,"per_page":50,"total":0}}')
$hugeb=Read-WebmaniaMonitorCompanyBatch -Client $c -Parameters $huge -MaximumItems 1
Check ($hugeb.Items.Count -eq 0 -and @($s.Requests)[-1].Target.Contains('page=2147483649')) 'exact large initial page and coherent out-of-range empty'
  @{requests=$s.Count
firstCount=$b.Items.Count
resumeCount=$end.Items.Count
continuationIndex=$b.Continuation.ItemIndex}
 }finally{Capture $s
$c.Dispose()
$s.Dispose()}
}
Probe @('POLL-02') 'direct and wait import invalido preserves declared erro plus native typed task output' {
 $s=[DeltaRawServer]::new()
$c=Monitor $s
$p=Input 'monitorGetImportStatus'
 try{
  foreach($withError in @($false,$true)){$body=@{uuid='00000000-0000-4000-8000-000000000001'
status='invalido'
processado=0
total=1
importados=@()
descartados=@()}
if($withError){$body.erro='synthetic terminal import detail'}
$text=$body|ConvertTo-Json -Compress
foreach($wait in @($false,$true)){$s.Json($text)
$r=if($wait){Wait-WebmaniaMonitorImport -Client $c -Parameters $p}else{Get-WebmaniaMonitorImportStatus -Client $c -Parameters $p}
Check ($r.Data.Status.Value -eq 'invalido' -and $r.Data.Erro.IsSet -eq $withError) 'typed terminal state including erro'}}
  $s.Json('{"error":"synthetic real business error"}')
$null=Failure {Wait-WebmaniaMonitorImport -Client $c -Parameters $p} 'business'
  $s.Json('{"uuid":"00000000-0000-4000-8000-000000000001","status":"concluido","processado":0,"importados":[],"descartados":[]}')
$task=Wait-WebmaniaMonitorImport -Client $c -Parameters $p -AsTask
Check ($task -is [Threading.Tasks.Task[Webmania.ApiResponse[Webmania.Api2MonitorDocumentsMonitorImportStatus]]]) 'wait underlying typed Task'
$null=$task.GetAwaiter().GetResult()
@{requests=$s.Count}
 }finally{Capture $s
$c.Dispose()
$s.Dispose()}
}
Probe @('TYPE-01','TYPE-03','TYPE-04','NUM-01') 'native typed fields, case-distinct extensions, open alternative and semantic integer projection' {
 $s=[DeltaRawServer]::new()
$c=Company $s
$m=Monitor $s
 try{
  $s.Json('{"uuid":"00000000-0000-4000-8000-000000000001","STATUS":"extra","status":"concluido","UUID":"distinct","message":{"future":true}}')
$p=[Webmania.NfeGetDocumentParameters]::new()
$p.ID=[Webmania.Optional[string]]::Of('typed-alpha6')
$r=Get-WebmaniaNfeDocument -Client $c -Parameters $p
$typed=$r.Data.AsVariant1().AsVariant1()
Check ($typed.Status.Value -eq 'concluido' -and $typed.Extras['STATUS'].GetString() -eq 'extra' -and $typed.Extras['UUID'].GetString() -eq 'distinct') 'exact case binding and extension fields'
Check ($typed.Extras['message'].GetProperty('future').GetBoolean()) 'other open branch retains object message'
  $body=[Webmania.Api2MonitorManagementMonitorCreateCompanyRequest]::new()
$body.Cnpj=[Webmania.Optional[string]]::Of('00000000000000')
$body.RazaoSocial=[Webmania.Optional[string]]::Of('Typed Alpha6')
$body.Cep=[Webmania.Optional[string]]::Of('01001000')
$body.CertificadoBase64=[Webmania.Optional[string]]::Of('PHRlc3QvPg==')
$body.CertificadoSenha=[Webmania.Optional[string]]::Of('synthetic-pass')
$create=[Webmania.MonitorCreateCompanyParameters]::new()
$create.Body=[Webmania.Optional[Webmania.Api2MonitorManagementMonitorCreateCompanyRequest]]::Of($body)
$s.Json('{"uuid":"00000000-0000-4000-8000-000000000001"}',201)
$null=New-WebmaniaMonitorCompany -Client $m -Parameters $create
Check (@($s.Requests)[-1].Body.Contains('Typed Alpha6')) 'normal typed body constructor wire'
  foreach($number in @('1.0','1e0')){$s.Json('{"expiration":'+$number+'}')
$r=Cert $c
Check ($r.Data.AsVariant1().Expiration.Value.Text -eq $number) 'semantic integer exact text'}
  @{requests=$s.Count
typedConstruction=$true
caseDistinct=$true}
 }finally{Capture $s
$c.Dispose()
$m.Dispose()
$s.Dispose()}
}
Probe @('FILE-01','FILE-02','FILE-03','FILE-04','FILE-06') 'file status/structure/readiness controls and corrected XLSX sheet/part fixtures' {
 $s=[PsSocketFixture]::new($false)
$o=Options $s
$c=New-WebmaniaApi1ReportCapabilityClient -Options $o
$p=Input 'fiscalDownloadReport'
$writes=0
 try{
  foreach($media in @('application/pdf','application/zip','text/csv','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')){$s.File($media)
$r=Receive-WebmaniaFiscalReport -Client $c -Parameters $p
Check ($r.IsFile) "declared format $media"}
  $s.Media='application/pdf'
$s.Body=[PsSocketFixture]::Pdf()
$s.Status=201
$null=Failure {Receive-WebmaniaFiscalReport -Client $c -Parameters $p} 'protocol'
$s.Status=200
  foreach($profile in @('unsupported','protected')){$s.Body=[PsSocketFixture]::Pdf(($profile -eq 'unsupported'),($profile -eq 'protected'))
$r=Receive-WebmaniaFiscalReport -Client $c -Parameters $p
Check (-not $r.IsFile) "$profile not ready"
$path=Join-Path $OutputDirectory ($profile+'.pdf')
$null=Failure {$r|Save-WebmaniaFile -LiteralPath $path} 'LocalValidation'
Check (-not(Test-Path $path)) 'nonready no file write'}
  $s.Body=[Text.Encoding]::UTF8.GetBytes('%PDF-1.7 malformed %%EOF')
$null=Failure {Receive-WebmaniaFiscalReport -Client $c -Parameters $p} 'protocol'
  $s.Media='application/zip'
$s.Body=[byte[]]@(80,75,3,4,0)
$null=Failure {Receive-WebmaniaFiscalReport -Client $c -Parameters $p} 'protocol'
  $s.Media='application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
$s.Body=[PsSocketFixture]::Spreadsheet(8,$false)
$r=Receive-WebmaniaFiscalReport -Client $c -Parameters $p
Check ($r.IsFile) 'eight actual sheets each use a distinct worksheet part'
$s.Body=[PsSocketFixture]::Spreadsheet(1,$false,$true,8)
$r=Receive-WebmaniaFiscalReport -Client $c -Parameters $p
Check ($r.IsFile) 'one actual sheet eight relationships to one part only rId1 used'
$s.Body=[PsSocketFixture]::Spreadsheet(8,$false,$true,8)
$historical=Receive-WebmaniaFiscalReport -Client $c -Parameters $p
$aliasProfile=@{actualSheets=8;worksheetParts=1;engineIsFile=$historical.IsFile;normativeOOXMLValidClaim=$false;meaning='historical bounded-profile acceptance only'}
  $s.Body=[PsSocketFixture]::Spreadsheet(2,$true)
$null=Failure {Receive-WebmaniaFiscalReport -Client $c -Parameters $p} 'protocol'
  $parts=[Collections.Generic.Dictionary[string,string]]::new()
$parts.Add('[Content_Types].xml','synthetic')
$parts.Add('xl/workbook.xml','synthetic')
$s.Body=[PsSocketFixture]::ZipParts($parts)
$null=Failure {Receive-WebmaniaFiscalReport -Client $c -Parameters $p} 'protocol'
  @{requests=$s.Requests.Count
nonreadyWrites=0
actualSheets=8;actualWorksheetParts=8;repeatedReferenceActualSheets=1;repeatedRelationships=8;historicalAliasProfile=$aliasProfile
numericDuplicateRejected=$true
legacyMalformedXlsxRejected=$true}
 }finally{Capture $s
$c.Dispose()
$s.Dispose()}
}
Probe @('CANCEL-01','CANCEL-04') 'queued runspace native Stop before dispatch and fresh sibling request' {
 $s=[IndependentServer]::new()
$o=[Webmania.WebmaniaClientOptions]::new()
$o.LoopbackTestEndpoint=$s.Url
$c=New-WebmaniaMonitorClient -Bearer $secret -Options $o
 $pool=[runspacefactory]::CreateRunspacePool(1,1)
$pool.Open()
$hold=[powershell]::Create()
$queued=[powershell]::Create()
$gate=[Threading.ManualResetEventSlim]::new($false)
$started=[Threading.ManualResetEventSlim]::new($false)
 try{
  $hold.RunspacePool=$pool
$null=$hold.AddScript('param($started,$gate);$started.Set();$gate.Wait()').AddArgument($started).AddArgument($gate)
$holding=$hold.BeginInvoke()
Check ($started.Wait(2000)) 'pool occupied positive control'
  $queued.RunspacePool=$pool
$null=$queued.AddScript('param($manifest,$client);Import-Module $manifest;Get-WebmaniaMonitorCompanies -Client $client -Parameters ([Webmania.MonitorListCompaniesParameters]::new())').AddArgument($manifest).AddArgument($c)
$pending=$queued.BeginInvoke()
[Threading.Thread]::Sleep(50)
$watch=[Diagnostics.Stopwatch]::StartNew()
$queued.Stop()
Check ($watch.ElapsedMilliseconds -lt 800 -and $s.Count -eq 0) 'queued stop zeroHTTP'
$gate.Set()
$null=$hold.EndInvoke($holding)
try{$null=$queued.EndInvoke($pending)}catch{}
  $s.Enqueue([IndependentReply]@{Body='{"data":[],"meta":{"current_page":1,"last_page":1,"per_page":50,"total":0}}'})
$null=Get-WebmaniaMonitorCompanies -Client $c -Parameters ([Webmania.MonitorListCompaniesParameters]::new())
Check ($s.Count -eq 1) 'fresh sibling unaffected'
@{queuedRequests=0
siblingRequests=$s.Count}
 }finally{$gate.Set()
$hold.Dispose()
$queued.Dispose()
$pool.Dispose()
$gate.Dispose()
$started.Dispose()
Capture $s
$c.Dispose()
$s.Dispose()}
}
Probe @('CANCEL-02') 'TLS ClientHello cancel/deadline closes peer before application HTTP' {
 foreach($caller in @($true,$false)){$peer=[DeltaHandshakePeer]::new()
$cts=[Threading.CancellationTokenSource]::new()
$o=[Webmania.WebmaniaClientOptions]::new()
$o.ServiceEndpoint=[uri]"https://127.0.0.1:$($peer.Port)/"
$o.Timeout=[timespan]::FromMilliseconds($(if($caller){1500}else{250}))
$c=New-WebmaniaCompanyClient -ConsumerKey $secret -ConsumerSecret $secret -AccessToken $secret -AccessTokenSecret $secret -Options $o
 try{if($caller){$cts.CancelAfter(150)}
$task=Set-WebmaniaFiscalCompany -Client $c -Parameters (Input 'fiscalUpdateCompany') -CancellationToken $cts.Token -AsTask
$watch=[Diagnostics.Stopwatch]::StartNew()
$e=Failure {$task.GetAwaiter().GetResult()}
$d=Diagnostic $e
$wait=[Diagnostics.Stopwatch]::StartNew()
while(-not $peer.Closed -and $wait.ElapsedMilliseconds -lt 500){[Threading.Thread]::Sleep(5)}
Check ($peer.Bytes -gt 0 -and $peer.Closed -and $peer.Accepts -eq 1) 'ClientHello observed then socket closed'
Check ($null -ne $d -and -not $d.OutcomeUncertain -and $d.Kind -eq $(if($caller){'cancelled'}else{'timeout'})) 'preHTTP context'
Check ($watch.ElapsedMilliseconds -lt 1000 -and $task.IsCanceled -eq $caller) 'bounded native task completion'}finally{$c.Dispose()
$cts.Dispose()
$peer.Dispose()}}
 @{modes=@('caller','deadline')
httpRequests=0
peerClosure=$true}
}
Probe @('CANCEL-02') 'real backlog pending TCP cancellation releases SYN before completion' {
 $backlog=[DeltaBacklog]::new()
$cts=[Threading.CancellationTokenSource]::new()
$o=[Webmania.WebmaniaClientOptions]::new()
$o.LoopbackTestEndpoint=[uri]"http://127.0.0.1:$($backlog.Port)/"
$o.Timeout=[timespan]::FromSeconds(2)
$c=New-WebmaniaCompanyClient -ConsumerKey $secret -ConsumerSecret $secret -AccessToken $secret -AccessTokenSecret $secret -Options $o
 try{$task=Set-WebmaniaFiscalCompany -Client $c -Parameters (Input 'fiscalUpdateCompany') -CancellationToken $cts.Token -AsTask
[Threading.Thread]::Sleep(80)
Check (-not $task.IsCompleted -and $backlog.SynSent -gt 0) 'native pending SYN positive'
$cts.Cancel()
$e=Failure {$task.GetAwaiter().GetResult()}
$d=Diagnostic $e
Check ($task.IsCanceled -and $d.Kind -eq 'cancelled' -and -not $d.OutcomeUncertain -and $backlog.SynSent -eq 0) 'preHTTP SYN released'
[Threading.Thread]::Sleep(180)
Check ($backlog.SynSent -eq 0) 'no late SYN'
@{httpRequests=0
pendingPositive=$true
postCompletionSyns=0}}finally{$c.Dispose()
$cts.Dispose()
$backlog.Dispose()}
}
Probe @('CANCEL-03') 'DNS child reaped, no secret argv/environment, no late packets and independent hostname sibling' {
 $original=[IO.File]::ReadAllText('/etc/resolv.conf')
$dns=[DeltaDnsPeer]::new()
$details=[Collections.Generic.List[object]]::new()
 try{
  [IO.File]::WriteAllText('/etc/resolv.conf',"nameserver 127.0.0.1`noptions timeout:1 attempts:2`n")
$env:WEBMANIA_ALPHA6_SYNTHETIC='ALPHA6-ENV-SENTINEL'
  foreach($caller in @($true,$false)){$cts=[Threading.CancellationTokenSource]::new()
$o=[Webmania.WebmaniaClientOptions]::new()
$hostName='blocked-alpha6-'+$(if($caller){'caller'}else{'deadline'})+'.test'
$o.ServiceEndpoint=[uri]"https://$hostName/"
$o.Timeout=[timespan]::FromMilliseconds($(if($caller){1500}else{350}))
$c=New-WebmaniaCompanyClient -ConsumerKey $secret -ConsumerSecret $secret -AccessToken $secret -AccessTokenSecret $secret -Options $o
   try{$task=Set-WebmaniaFiscalCompany -Client $c -Parameters (Input 'fiscalUpdateCompany') -CancellationToken $cts.Token -AsTask
$child=0
$argv=''
$environment=''
$watch=[Diagnostics.Stopwatch]::StartNew()
    while($child -eq 0 -and $watch.ElapsedMilliseconds -lt 800){foreach($dir in [IO.Directory]::GetDirectories('/proc')){$name=[IO.Path]::GetFileName($dir)
if($name -notmatch '^[0-9]+$'){continue}
try{$cmd=[IO.File]::ReadAllText($dir+'/cmdline')
if($cmd.Contains('Webmania.DnsHelper.dll')){$child=[int]$name
$argv=$cmd
$environment=[IO.File]::ReadAllText($dir+'/environ')
break}}catch{}}
if($child -eq 0){[Threading.Thread]::Sleep(5)}}
    Check ($child -gt 0 -and -not $argv.Contains($hostName) -and -not $environment.Contains('ALPHA6-ENV-SENTINEL')) 'owned helper child no private argv/env'
    if($caller){
     $dnsWait=[Diagnostics.Stopwatch]::StartNew()
     while(@($dns.Queries|Where-Object Host -eq $hostName).Count -eq 0 -and $dnsWait.ElapsedMilliseconds -lt 1000){[Threading.Thread]::Sleep(5)}
     Check (@($dns.Queries|Where-Object Host -eq $hostName).Count -gt 0) 'blocked resolver received positive caller DNS query'
     $cts.Cancel()
    }
$e=Failure {$task.GetAwaiter().GetResult()}
$d=Diagnostic $e
$done=$dns.Milliseconds
Check ($null -ne $d -and $d.Kind -eq $(if($caller){'cancelled'}else{'timeout'}) -and -not $d.OutcomeUncertain -and -not(Test-Path "/proc/$child")) 'completion child reaped'
Check ($task.IsCanceled -eq $caller) 'DNS native Task state'
[Threading.Thread]::Sleep(1100)
Check (@($dns.Queries|Where-Object {$_.Host -eq $hostName -and $_.Milliseconds -gt $done+40}).Count -eq 0) 'no late resolver packet'
$details.Add(@{caller=$caller
processReaped=$true
lateQueries=0
kind=$d.Kind})
   }finally{$c.Dispose()
$cts.Dispose()}}
  $s=[DeltaRawServer]::new()
$o=Options $s
$o.LoopbackTestEndpoint=[uri]"http://localhost:$($s.Port)/"
$c=New-WebmaniaCompanyClient -ConsumerKey $secret -ConsumerSecret $secret -AccessToken $secret -AccessTokenSecret $secret -Options $o
  try{$s.Json('{"expiration":1}')
$null=Cert $c
Check ($s.Count -eq 1) 'new hostname resolution after canceled sibling'
Capture $s}finally{$c.Dispose()
$s.Dispose()}
@{details=@($details)
queries=@($dns.Queries)
freshHostnameRequests=1}
 }finally{[IO.File]::WriteAllText('/etc/resolv.conf',$original)
$env:WEBMANIA_ALPHA6_SYNTHETIC=$null
$dns.Dispose()}
}
. (Join-Path $PSScriptRoot 'DeltaPrivacy.ps1')
# Persist failures as well as passes. This suite is author evidence, never inherited engine acceptance.
$failed=@($observations|Where-Object status -eq 'fail')
@{status=$(if($failed.Count){'fail'}else{'pass'})
assertions=$script:assertions
observationCount=$observations.Count
failed=$failed.Count
archiveSha256=(Get-FileHash $Archive).Hash.ToLowerInvariant()
observations=@($observations)
applicationRequests=$wire.Count
httpRequests=@($wire|Where-Object scheme -eq 'http').Count
httpsRequests=@($wire|Where-Object scheme -eq 'https').Count
externalApiCalls=0
attribution='New PowerShell public-consumer delta, using author wire peers and retained lifecycle fixture; no .NET acceptance inherited'}|ConvertTo-Json -Depth 20|Set-Content (Join-Path $OutputDirectory 'delta-results.json')
ConvertTo-Json -InputObject @($wire) -Depth 16|Set-Content (Join-Path $OutputDirectory 'delta-wire.json')
Write-Output "Delta: $($observations.Count) observations; $script:assertions assertions; $($failed.Count) failures; $($wire.Count) captured application requests"
if($failed.Count){throw 'PowerShell delta contains failures; receipts retained.'}
