param([Parameter(Mandatory)][string]$Archive,[Parameter(Mandatory)][string]$OutputDirectory)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
trap { Write-Output $_.ToString(); Write-Output $_.ScriptStackTrace; throw $_ }
$root=Split-Path $PSScriptRoot
$checks=[Collections.Generic.List[object]]::new()
function Assert([bool]$Condition,[string]$Name){if(-not $Condition){throw "Assertion failed: $Name"};$checks.Add(@{name=$Name;status='pass'})}
function Reject([string]$Name,[scriptblock]$Action,[string]$Kind=''){
    $caught=$null;try{&$Action|Out-Null}catch{$caught=$_}
    Assert ($null -ne $caught) "$Name rejected"
    if($Kind){Assert ($caught.FullyQualifiedErrorId -like "Webmania.$Kind,*") "$Name protected kind"}
    return $caught
}
$install=Join-Path '/tmp' ('ps-consumer-'+[guid]::NewGuid().ToString('N'))
Expand-Archive -LiteralPath $Archive -DestinationPath $install
Assert (-not ([AppDomain]::CurrentDomain.GetAssemblies()|Where-Object {$_.GetName().Name -eq 'Webmania.Sdk'})) 'fresh process before import'
$modulePath=Join-Path $install 'Webmania/Webmania.psd1'
$info=Test-ModuleManifest $modulePath
Import-Module $modulePath -Force
Assert ([Webmania.WebmaniaClient].Assembly.Location -eq (Join-Path $install 'Webmania/bin/Webmania.Sdk.dll')) 'archive assembly loaded from isolated install'
Assert ((Get-FileHash -LiteralPath ([Webmania.WebmaniaClient].Assembly.Location)).Hash.ToLowerInvariant() -eq 'c7a6f33f12d326ab56a0fd94c692eb93a818c6a8588e1097bfcdf16506e0e2b9') 'exact dependency bytes'
Assert ($info.PrivateData.PSData.Prerelease -eq 'alpha7') 'archive prerelease manifest'
Assert ((Get-Module Webmania).ExportedCommands.Count -eq 126) 'all 126 public commands exported'
foreach($command in (Get-Command -Module Webmania)){Assert ($command.Verb -in (Get-Verb).Verb) "approved exported verb $($command.Name)"}
$catalog=Get-Content (Join-Path $install 'Webmania/commands.json') -Raw|ConvertFrom-Json
$fixtures=Get-Content (Join-Path $PSScriptRoot 'fixtures/fixtures.json') -Raw|ConvertFrom-Json -AsHashtable
$ops=Get-Content (Join-Path $PSScriptRoot 'fixtures/operations.json') -Raw|ConvertFrom-Json -AsHashtable
$byId=@{};foreach($f in $fixtures){$byId[$f.id]=$f}
$wireOps=@{};foreach($o in $ops){$wireOps[$o.id]=$o}
foreach($entry in $catalog){
    $command=Get-Command $entry.command
    Assert ($command.Parameters.Parameters.ParameterType.FullName -eq $entry.parametersType) "exact typed binder $($entry.operationId)"
    Assert ($command.Verb -in (Get-Verb).Verb) "approved verb $($entry.command)"
}
Add-Type -Path (Join-Path $PSScriptRoot 'SocketFixture.cs')
$secure=@{};foreach($name in @('key','secret','access','access-secret','issuer','monitor','files','document+token/=')){$secure[$name]=ConvertTo-SecureString ('synthetic-'+$name) -AsPlainText -Force}
function New-ScopedClient([string]$Scope,[string]$Mode,[Webmania.WebmaniaClientOptions]$Options){
    $four=@{ConsumerKey=$secure.key;ConsumerSecret=$secure.secret;AccessToken=$secure.access;AccessTokenSecret=$secure.'access-secret';Options=$Options}
    switch($Scope){
        'company'{New-WebmaniaCompanyClient @four}
        'reseller'{New-WebmaniaResellerClient @four}
        'issuer'{New-WebmaniaIssuerClient -Bearer $secure.issuer -Options $Options}
        'monitor'{New-WebmaniaMonitorClient -Bearer $secure.monitor -Options $Options}
        'api1-files'{if($Mode -eq 'token'){New-WebmaniaApi1FilesDocumentTokenClient -Token $secure.'document+token/=' -Options $Options}else{New-WebmaniaApi1FilesCompanyClient @four}}
        'api2-files'{switch($Mode){'token'{New-WebmaniaApi2FilesDocumentTokenClient -Token $secure.'document+token/=' -Options $Options};'anonymous'{New-WebmaniaApi2FilesAnonymousClient -Options $Options};default{New-WebmaniaApi2FilesCompanyBearerClient -Bearer $secure.files -Options $Options}}}
        'report-file'{New-WebmaniaApi1ReportCapabilityClient -Options $Options}
    }
}
function TypedInput($Entry,$Fixture){
    [Text.Json.JsonSerializer]::Deserialize((ConvertTo-Json -InputObject $Fixture.input -Depth 96 -Compress),([type]$Entry.parametersType),[Webmania.WebmaniaJson]::Options)
}
$results=[Collections.Generic.List[object]]::new();$wire=[Collections.Generic.List[object]]::new()
foreach($tls in @($false,$true)){
    $server=[PsSocketFixture]::new($tls)
    $options=[Webmania.WebmaniaClientOptions]::new();$options.Timeout=[timespan]::FromSeconds(5)
    if($tls){$options.LoopbackTestEndpoint=[uri]"https://localhost:$($server.Port)/";$options.LoopbackTestRootCertificate=[Security.Cryptography.X509Certificates.X509CertificateLoader]::LoadCertificate($server.CertificateDer)}
    else{$options.LoopbackTestEndpoint=[uri]"http://127.0.0.1:$($server.Port)/"}
    try{
        $monitor=New-ScopedClient 'monitor' 'company' $options
        try{
            Reject 'wrong typed DTO binder' {Get-WebmaniaMonitorCompanies -Client $monitor -Parameters ([datetime]::UtcNow)}|Out-Null
            Reject 'empty secure credential' {New-WebmaniaMonitorClient -Bearer ([Security.SecureString]::new()) -Options $options} 'LocalValidation'|Out-Null
            Reject 'wrong credential scope' {Get-WebmaniaNfeDocument -Client $monitor -Parameters ([Webmania.NfeGetDocumentParameters]::new())} 'credential_scope'|Out-Null
            $bad=[Webmania.MonitorListCompaniesParameters]::new();$bad.PerPage=[Webmania.Optional[Webmania.JsonNumber]]::Of([Webmania.JsonNumber]::new('2'))
            Reject 'invalid page size' {Get-WebmaniaMonitorCompanies -Client $monitor -Parameters $bad} 'validation'|Out-Null
            Reject 'invalid exact number' {New-WebmaniaJsonNumber -Text '01'} 'LocalValidation'|Out-Null
            Reject 'invalid page bound' {Get-WebmaniaMonitorCompanyItem -Client $monitor -Parameters ([Webmania.MonitorListCompaniesParameters]::new()) -MaximumPages 0}|Out-Null
            $company=New-ScopedClient 'company' 'company' $options
            try{Reject 'missing fiscal selector' {Get-WebmaniaNfeDocument -Client $company -Parameters ([Webmania.NfeGetDocumentParameters]::new())} 'validation'|Out-Null}finally{$company.Dispose()}
            Assert ($server.Requests.Count -eq 0) "all invalid binding/auth/input cases zero I/O TLS=$tls"
        }finally{$monitor.Dispose()}
        foreach($entry in $catalog){
            $fixture=$byId[$entry.operationId];$op=$wireOps[$entry.operationId]
            Assert ($fixture.requestValid -and $fixture.responseValid) "frozen fixture declared valid $($entry.operationId)"
            $modes=if($entry.scope -eq 'api1-files'){@('company','token')}elseif($entry.scope -eq 'api2-files' -and $op.route -notlike '*mdfe*'){@('company','token','anonymous')}else{@('company')}
            foreach($mode in $modes){
                # The current report download uses its own capability client; the legacy one stays on the API1 capability.
                $client=if($entry.operationId -eq 'fiscalDownloadReportV2'){New-WebmaniaReportCapabilityClient -Options $options}else{New-ScopedClient $entry.scope $mode $options}
                try{
                    if($op.binary){$media=@($op.responseMedia|Where-Object {$_ -notin @('application/json','text/html')})[0];$server.File($media)}else{$server.Json((ConvertTo-Json -InputObject $fixture.response -Depth 96 -Compress))}
                    # preview4 enforces each declared success status; historical all-200 fixture was too permissive.
                    $statusKey=@($op.responseSelections.Keys|Where-Object {$_ -match '^2[0-9][0-9]$'}|Sort-Object)[0]
                    $successStatus=if($statusKey){[int]$statusKey}else{200}
                    $server.Status=$successStatus
                    $parameters=TypedInput $entry $fixture
                    $before=$server.Requests.Count
                    if(-not $entry.enabled){
                        Reject 'blocked contract capability' {& $entry.command -Client $client -Parameters $parameters} 'capability_unavailable'|Out-Null
                        Assert ($server.Requests.Count -eq $before) 'blocked operation zero I/O'
                        $results.Add(@{operationId=$entry.operationId;tls=$tls;mode=$mode;status='blocked-as-designed'})
                        continue
                    }
                    $result=& $entry.command -Client $client -Parameters $parameters
                    Assert ($result.GetType() -eq [type]$entry.outputType) "typed output $($entry.operationId) TLS=$tls mode=$mode"
                    Assert ($result.StatusCode -eq $successStatus) "declared $successStatus $($entry.operationId)"
                    Assert ($server.Requests.Count -eq $before+1) "one request $($entry.operationId)"
                    $request=$server.Requests.ToArray()[-1]
                    Assert ($request.Method -eq $op.method) "wire method $($entry.operationId)"
                    $route=$op.route
                    foreach($p in $op.parameters){if($p.in -eq 'path' -and $fixture.input.ContainsKey($p.name)){$route=$route.Replace('{'+$p.name+'}',[uri]::EscapeDataString([string]$fixture.input[$p.name]))}}
                    Assert ($request.Target.Split('?')[0] -ceq $route) "wire route $($entry.operationId)"
                    $query=[Collections.Generic.Dictionary[string,string]]::new([StringComparer]::Ordinal);if($request.Target.Contains('?')){foreach($pair in $request.Target.Split('?',2)[1].Split('&')){$kv=$pair.Split('=',2);$query[[uri]::UnescapeDataString($kv[0])]=[uri]::UnescapeDataString($kv[1])}}
                    foreach($p in $op.parameters){if($p.in -eq 'query' -and $fixture.input.ContainsKey($p.name)){
                        $queryValue=if($fixture.input[$p.name] -is [string]){$fixture.input[$p.name]}else{ConvertTo-Json -InputObject $fixture.input[$p.name] -Compress}
                        Assert ($query[$p.name] -ceq $queryValue) "exact query $($entry.operationId) $($p.name)"
                    }}
                    if($fixture.input.ContainsKey('body')){
                        $expected=[Text.Json.JsonDocument]::Parse((ConvertTo-Json -InputObject $fixture.input.body -Depth 96 -Compress));$actual=[Text.Json.JsonDocument]::Parse($request.Body)
                        try{Assert ([Text.Json.JsonElement]::DeepEquals($expected.RootElement,$actual.RootElement)) "body preserved $($entry.operationId)"}finally{$expected.Dispose();$actual.Dispose()}
                    }else{Assert ($request.Body.Length -eq 0 -and $request.Headers['content-length'] -eq '0' -and -not $request.Headers.ContainsKey('content-type')) "bodyless wire $($entry.operationId)"}
                    $four=$entry.scope -in @('company','reseller') -or ($entry.scope -eq 'api1-files' -and $mode -eq 'company')
                    foreach($h in @('x-consumer-key','x-consumer-secret','x-access-token','x-access-token-secret')){Assert ($request.Headers.ContainsKey($h) -eq $four) "four header scope $($entry.operationId) $h"}
                    if($four){Assert ($request.Headers['x-consumer-key'] -eq 'synthetic-key' -and $request.Headers['x-consumer-secret'] -eq 'synthetic-secret' -and $request.Headers['x-access-token'] -eq 'synthetic-access' -and $request.Headers['x-access-token-secret'] -eq 'synthetic-access-secret') "exact four credentials $($entry.operationId)"}
                    $bearer=$entry.scope -in @('issuer','monitor') -or ($entry.scope -eq 'api2-files' -and $mode -eq 'company')
                    Assert ($request.Headers.ContainsKey('authorization') -eq $bearer) "bearer scope $($entry.operationId)"
                    if($bearer){$token=if($entry.scope -eq 'api2-files'){'files'}else{$entry.scope};Assert ($request.Headers['authorization'] -eq "Bearer synthetic-$token") "exact bearer $($entry.operationId)"}
                    Assert ($request.Target.Contains('token=synthetic-document%2Btoken%2F%3D') -eq ($mode -eq 'token')) "token mode encoded once $($entry.operationId)"
                    Assert (-not $request.Headers.ContainsKey('x-token')) "no X-Token fallback $($entry.operationId)"
                    if($op.binary){Assert ([Convert]::ToBase64String($result.Bytes.ToArray()) -eq [Convert]::ToBase64String($server.Body)) "file bytes intact $($entry.operationId)"}
                    else{Assert ($null -ne $result.Data) "public typed data $($entry.operationId)"}
                    $wire.Add(@{operationId=$entry.operationId;tls=$tls;mode=$mode;request=$request})
                    $results.Add(@{operationId=$entry.operationId;tls=$tls;mode=$mode;status='pass';responseType=$result.GetType().ToString()})
                }finally{$client.Dispose()}
            }
        }
        Assert ($server.Errors.Count -eq 0) "fixture errors absent TLS=$tls"
        Write-Output "Operation matrix TLS=${tls}: $($server.Requests.Count) actual socket requests"
    }finally{$server.Dispose()}
}
# Extra checks are actual commands loaded from the same archive.
. (Join-Path $PSScriptRoot 'Regressions.ps1')
# A module root whose name is a wildcard pattern imports only its literal files (fresh process).
$pwsh=(Get-Command pwsh -CommandType Application|Select-Object -First 1).Source
$probe=& $pwsh -NoLogo -NoProfile -NonInteractive -File (Join-Path $PSScriptRoot 'Import-Probe.ps1') -Case wildcard-root -Archive $Archive -OutputDirectory $OutputDirectory 2>&1
Assert ($LASTEXITCODE -eq 0 -and "$probe".Contains('PASS: wildcard-root')) ('wildcard-named module root loads only literal files: '+"$probe")
# The neutral homologation example against a loopback fixture: blocked without WEBMANIA_LIVE=1,
# masked lines, ledger, one request per mutation, an unknown outcome is never repeated.
$exampleScript=[IO.Path]::Combine($root,'examples','homologacao','run.ps1')
function Invoke-Example([hashtable]$Environment,[switch]$NoWait){
    $psi=[Diagnostics.ProcessStartInfo]::new($pwsh)
    # -NoWait runs the same script with Start-Sleep replaced, so every consult attempt runs at once.
    $invocation=if($NoWait){@('-Command',"function global:Start-Sleep {}; & '$($exampleScript.Replace("'","''"))'; exit `$LASTEXITCODE")}else{@('-File',$exampleScript)}
    foreach($argument in @('-NoLogo','-NoProfile','-NonInteractive')+$invocation){$psi.ArgumentList.Add($argument)}
    $psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true;$psi.UseShellExecute=$false
    foreach($key in @($psi.Environment.Keys|Where-Object {$_ -like 'WEBMANIA_*'})){[void]$psi.Environment.Remove($key)}
    foreach($key in $Environment.Keys){$psi.Environment[$key]=$Environment[$key]}
    $process=[Diagnostics.Process]::Start($psi);$stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync();$process.WaitForExit()
    @{Code=$process.ExitCode;Stdout=$stdout.Result;Stderr=$stderr.Result}
}
function Read-Lines([string]$Text){@($Text -split "`n"|Where-Object {$_.Trim()}|ForEach-Object {$_|ConvertFrom-Json})}
$exampleServer=[PsSocketFixture]::new($false)
$exampleDirectory=Join-Path '/tmp' ('ps-example-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory $exampleDirectory|Out-Null
try{
    $blocked=Invoke-Example @{}
    Assert ($blocked.Code -eq 77 -and $blocked.Stdout.Trim() -eq '{"result":"blocked"}' -and $exampleServer.Requests.Count -eq 0) 'example blocked before any request without WEBMANIA_LIVE=1'
    $nfeUuid='11111111-1111-4111-8111-1111111111a1';$nfseUuid='11111111-1111-4111-8111-1111111111b2'
    $fixtureText=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'fixtures/fixtures.json'))
    $exampleServer.Routes=[PsExampleRoutes]::new([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'fixtures/operations.json')),$fixtureText,$nfeUuid,$nfseUuid)
    [IO.File]::WriteAllText((Join-Path $exampleDirectory 'nfe.json'),[PsExampleRoutes]::Payload($fixtureText,'nfeIssueDocument'))
    [IO.File]::WriteAllText((Join-Path $exampleDirectory 'nfse.json'),[PsExampleRoutes]::Payload($fixtureText,'emitterIssueNfse'))
    $origin="http://127.0.0.1:$($exampleServer.Port)";$ledger=Join-Path $exampleDirectory 'ledger.jsonl'
    $exampleSecrets=@{WEBMANIA_CONSUMER_KEY='example-key-value';WEBMANIA_CONSUMER_SECRET='example-secret-value';WEBMANIA_ACCESS_TOKEN='example-access-value';WEBMANIA_ACCESS_TOKEN_SECRET='example-access-secret-value';WEBMANIA_ISSUER_TOKEN='example-issuer-value'}
    $exampleEnvironment=@{WEBMANIA_LIVE='1';WEBMANIA_LIVE_SCOPE='all';WEBMANIA_API1_BASE_URL="$origin/api";WEBMANIA_FILES_BASE_URL=$origin;WEBMANIA_API2_BASE_URL=$origin;WEBMANIA_LIVE_ALLOWED_HOSTS='127.0.0.1';WEBMANIA_LIVE_LEDGER=$ledger;WEBMANIA_LIVE_NFE_PAYLOAD=(Join-Path $exampleDirectory 'nfe.json');WEBMANIA_LIVE_NFSE_PAYLOAD=(Join-Path $exampleDirectory 'nfse.json')}
    foreach($key in $exampleSecrets.Keys){$exampleEnvironment[$key]=$exampleSecrets[$key]}
    $run=Invoke-Example $exampleEnvironment
    $lines=Read-Lines $run.Stdout
    Assert ($run.Code -eq 0 -and $lines.Count -gt 0 -and -not @($lines|Where-Object {-not $_.ok}).Count) ('example full cycle passes: '+$run.Stdout+$run.Stderr)
    $steps=@($lines.step)
    foreach($step in @('readonly.sefaz','readonly.certificate','readonly.tax_classes','readonly.nfse_provider','nfe.issue','nfe.consult','nfe.query','nfe.danfe','nfe.danfe_simple','nfe.xml','nfe.cancel','nfe.consult_cancelled','nfe.cancellation_xml','nfse.issue','nfse.consult','nfse.xml','nfse.pdf','nfse.rps_pdf','nfse.cancel','nfse.consult_cancelled')){Assert ($step -in $steps) "example step $step"}
    foreach($value in @($exampleSecrets.Values)+@($nfeUuid,$nfseUuid,$origin)){Assert (-not ($run.Stdout+$run.Stderr).Contains($value)) 'no private value in example output'}
    $entries=@([IO.File]::ReadAllLines($ledger)|ForEach-Object {$_|ConvertFrom-Json})
    Assert ((@($entries|ForEach-Object {$_.model+'|'+$_.identifier}|Sort-Object -Unique) -join ',') -eq "nfe|$nfeUuid,nfse|$nfseUuid") 'example ledger records both documents'
    Assert ((@($entries|Where-Object {$_.operation -in @('nfeCancelDocument','emitterCancelNfse')}|ForEach-Object status) -join ',') -eq 'cancelado,cancelado') 'example ledger records both cancellations'
    $requests=@($exampleServer.Requests.ToArray())
    Assert (@($requests|Where-Object {$_.Method -eq 'POST' -and $_.Target -eq '/1/nfe/emissao/'}).Count -eq 1 -and @($requests|Where-Object {$_.Method -eq 'POST' -and $_.Target -eq '/2/nfse/emissao'}).Count -eq 1) 'example sends one request per issue'
    Assert (@($requests|Where-Object Method -eq 'PUT').Count -eq 2) 'example sends one request per cancellation'
    $before=$requests.Count
    $outsideEnvironment=$exampleEnvironment.Clone();$outsideEnvironment.WEBMANIA_API1_BASE_URL='https://other.example.invalid/api'
    $outside=Invoke-Example $outsideEnvironment
    Assert ($outside.Code -eq 77 -and ($outside.Stdout|ConvertFrom-Json).reason -eq 'origin_not_allowed' -and $exampleServer.Requests.Count -eq $before) 'example refuses an origin outside the allow list before any request'
    foreach($hosts in @($null,' , ')){
        $unlisted=$exampleEnvironment.Clone();$unlisted.Remove('WEBMANIA_LIVE_ALLOWED_HOSTS');if($null -ne $hosts){$unlisted.WEBMANIA_LIVE_ALLOWED_HOSTS=$hosts}
        $refused=Invoke-Example $unlisted
        Assert ($refused.Code -eq 77 -and $refused.Stdout.Trim() -eq '{"result":"blocked","reason":"allowed_hosts"}' -and $exampleServer.Requests.Count -eq $before) 'example requires the allow list before credentials or any request'
    }
    # A mutation scope needs a writable ledger (unset, empty, a directory, a missing parent): 77 before any request.
    foreach($ledgerScope in @('nfe','nfse','all')){
        foreach($ledgerValue in @($null,'',$exampleDirectory,(Join-Path $exampleDirectory 'absent/ledger.jsonl'))){
            $unledgered=$exampleEnvironment.Clone();$unledgered.WEBMANIA_LIVE_SCOPE=$ledgerScope;$unledgered.Remove('WEBMANIA_LIVE_LEDGER');if($null -ne $ledgerValue){$unledgered.WEBMANIA_LIVE_LEDGER=$ledgerValue}
            $refused=Invoke-Example $unledgered
            Assert ($refused.Code -eq 77 -and $refused.Stdout.Trim() -eq '{"result":"blocked","reason":"ledger"}' -and $exampleServer.Requests.Count -eq $before) ("example $ledgerScope scope requires a writable ledger before any request: "+$refused.Stdout+$refused.Stderr)
        }
    }
    Assert (-not (Test-Path -LiteralPath (Join-Path $exampleDirectory 'absent'))) 'a missing ledger parent is not created'
    $exampleServer.Routes.FailIssue=$true;Remove-Item -LiteralPath $ledger
    $unknownEnvironment=$exampleEnvironment.Clone();$unknownEnvironment.WEBMANIA_LIVE_SCOPE='nfe'
    $unknown=Invoke-Example $unknownEnvironment
    $issueLines=@(Read-Lines $unknown.Stdout|Where-Object step -eq 'nfe.issue')
    Assert ($unknown.Code -eq 1 -and $issueLines.Count -eq 1 -and $issueLines[0].outcome -eq 'unknown') 'example stops on an unknown issue outcome'
    $after=@($exampleServer.Requests.ToArray()|Select-Object -Skip $before)
    Assert (@($after|Where-Object {$_.Method -eq 'POST' -and $_.Target -eq '/1/nfe/emissao/'}).Count -eq 1 -and -not @($after|Where-Object Method -eq 'PUT').Count) 'unknown outcome is never repeated or followed by a cancellation'
    $pending=[IO.File]::ReadAllText($ledger).Trim()|ConvertFrom-Json
    Assert ($pending.status -eq 'unknown' -and $pending.operation -eq 'nfeIssueDocument') 'unknown outcome recorded in the example ledger'
    # An unknown cancellation outcome is recorded in the ledger before the run stops (fresh document state per model).
    foreach($case in @(@{scope='nfe';uuid=$nfeUuid;operation='nfeCancelDocument'},@{scope='nfse';uuid=$nfseUuid;operation='emitterCancelNfse'})){
        $exampleServer.Routes=[PsExampleRoutes]::new([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'fixtures/operations.json')),$fixtureText,$nfeUuid,$nfseUuid);$exampleServer.Routes.FailCancel=$true
        Remove-Item -LiteralPath $ledger -ErrorAction SilentlyContinue
        $cancelEnvironment=$exampleEnvironment.Clone();$cancelEnvironment.WEBMANIA_LIVE_SCOPE=$case.scope
        $start=$exampleServer.Requests.Count
        $cancelRun=Invoke-Example $cancelEnvironment
        $cancelLines=@(Read-Lines $cancelRun.Stdout)
        $cancelSteps=@($cancelLines|Where-Object step -eq "$($case.scope).cancel")
        Assert ($cancelRun.Code -eq 1 -and $cancelSteps.Count -eq 1 -and $cancelSteps[0].outcome -eq 'unknown' -and -not @($cancelLines|Where-Object step -eq "$($case.scope).consult_cancelled").Count) ("example stops on an unknown $($case.scope) cancellation outcome: "+$cancelRun.Stdout+$cancelRun.Stderr)
        Assert (@($exampleServer.Requests.ToArray()|Select-Object -Skip $start|Where-Object Method -eq 'PUT').Count -eq 1) "unknown $($case.scope) cancellation is never repeated"
        $recorded=@([IO.File]::ReadAllLines($ledger)|ForEach-Object {$_|ConvertFrom-Json}|Where-Object operation -eq $case.operation)
        Assert ($recorded.Count -eq 1 -and $recorded[0].model -eq $case.scope -and $recorded[0].identifier -eq $case.uuid -and $recorded[0].status -eq 'unknown') "unknown $($case.scope) cancellation recorded in the example ledger"
    }
    # An accepted cancellation whose consult never shows "cancelado" fails the run.
    $exampleServer.Routes=[PsExampleRoutes]::new([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'fixtures/operations.json')),$fixtureText,$nfeUuid,$nfseUuid);$exampleServer.Routes.StuckCancel=$true
    Remove-Item -LiteralPath $ledger -ErrorAction SilentlyContinue
    $start=$exampleServer.Requests.Count
    $stuckRun=Invoke-Example $exampleEnvironment -NoWait
    $stuckLines=@(Read-Lines $stuckRun.Stdout)
    Assert ($stuckRun.Code -eq 1) ('a document that never shows cancelado fails the example run: '+$stuckRun.Stdout+$stuckRun.Stderr)
    foreach($case in @(@{scope='nfe';operation='nfeGetDocument';cancel='nfeCancelDocument'},@{scope='nfse';operation='emitterGetNfse';cancel='emitterCancelNfse'})){
        $verdict=@($stuckLines|Where-Object {$_.step -eq "$($case.scope).consult_cancelled" -and -not $_.ok})
        Assert ($verdict.Count -eq 1 -and $verdict[0].operation -eq $case.operation -and $verdict[0].kind -eq 'not_cancelled') "example reports a $($case.scope) final consult without cancelado as not_cancelled"
        $recorded=@([IO.File]::ReadAllLines($ledger)|ForEach-Object {$_|ConvertFrom-Json}|Where-Object operation -eq $case.cancel)
        Assert ($recorded.Count -eq 1 -and $recorded[0].status -eq 'aprovado') "example ledger keeps the $($case.scope) status the final consult observed"
    }
    Assert (-not @($stuckLines|Where-Object step -eq 'nfe.cancellation_xml').Count) 'no cancellation XML without cancelado'
    Assert (@($exampleServer.Requests.ToArray()|Select-Object -Skip $start|Where-Object Method -eq 'PUT').Count -eq 2) 'example sends one request per cancellation without cancelado'
    Assert ($exampleServer.Errors.Count -eq 0) 'example fixture errors absent'
    Write-Output "Homologation example: $($lines.Count) masked steps, $($exampleServer.Requests.Count) loopback requests"
}finally{$exampleServer.Dispose();Remove-Item -LiteralPath $exampleDirectory -Recurse -Force -ErrorAction SilentlyContinue}
# Packaging stages in a private temporary directory: an existing output directory (literal path, wildcard
# characters included) keeps its other contents, only the archive and its manifest are written, the bytes
# do not depend on the output location, and an output inside the packaged module tree is refused.
$packageScript=[IO.Path]::Combine($root,'scripts','Package.ps1')
$packageOutput=[IO.Path]::Combine('/tmp','ps-package-'+[guid]::NewGuid().ToString('N')+'[out]*')
try{
    [void][IO.Directory]::CreateDirectory([IO.Path]::Combine($packageOutput,'stage'))
    [IO.File]::WriteAllText([IO.Path]::Combine($packageOutput,'stage','keep.txt'),'keep')
    $packaged=& $pwsh -NoLogo -NoProfile -NonInteractive -File $packageScript -OutputDirectory $packageOutput 2>&1
    Assert ($LASTEXITCODE -eq 0) ('package into an existing directory: '+"$packaged")
    Assert ([IO.File]::ReadAllText([IO.Path]::Combine($packageOutput,'stage','keep.txt')) -eq 'keep') 'package keeps an existing stage directory in the output'
    $written=@([IO.Directory]::GetFileSystemEntries($packageOutput)|ForEach-Object {[IO.Path]::GetFileName($_)}|Sort-Object)
    Assert (($written -join ',') -eq ((@((Split-Path $Archive -Leaf),'package-manifest.json','stage')|Sort-Object) -join ',')) ('package writes only the archive and its manifest: '+($written -join ','))
    Assert ((Get-FileHash -LiteralPath ([IO.Path]::Combine($packageOutput,(Split-Path $Archive -Leaf)))).Hash -eq (Get-FileHash -LiteralPath $Archive).Hash) 'package bytes do not depend on the output directory'
    $inside=[IO.Path]::Combine($root,'module','Webmania','out-'+[guid]::NewGuid().ToString('N'))
    $refused=& $pwsh -NoLogo -NoProfile -NonInteractive -File $packageScript -OutputDirectory $inside 2>&1
    Assert ($LASTEXITCODE -ne 0 -and "$refused".Contains('outside module/Webmania') -and -not (Test-Path -LiteralPath $inside)) ('package refuses an output inside the module tree: '+"$refused")
}finally{if([IO.Directory]::Exists($packageOutput)){[IO.Directory]::Delete($packageOutput,$true)}}
@{psVersion=$PSVersionTable.PSVersion.ToString();dotnet=[Environment]::Version.ToString();os=[Runtime.InteropServices.RuntimeInformation]::OSDescription;architecture=[Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString();assembly=[Webmania.WebmaniaClient]::Version;archiveSha256=(Get-FileHash $Archive).Hash.ToLowerInvariant()}|ConvertTo-Json|Set-Content (Join-Path $OutputDirectory 'runtime.json')
$wire|ConvertTo-Json -Depth 12|Set-Content (Join-Path $OutputDirectory 'requests.json')
$results|ConvertTo-Json -Depth 6|Set-Content (Join-Path $OutputDirectory 'operation-results.json')
@{status='pass';checks=@($checks);checkCount=$checks.Count;operationCases=$results.Count;enabledOperationIds=@($results|Where-Object status -eq 'pass'|Select-Object -ExpandProperty operationId -Unique).Count;blockedOperationIds=@($results|Where-Object status -eq 'blocked-as-designed'|Select-Object -ExpandProperty operationId -Unique).Count;matrixRequests=$wire.Count;externalApiCalls=0}|ConvertTo-Json -Depth 8|Set-Content (Join-Path $OutputDirectory 'results.json')
Write-Output "PASS: $($checks.Count) checks; $($results.Count) operation cases; $($wire.Count) matrix requests"
