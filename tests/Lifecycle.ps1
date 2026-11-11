param([Parameter(Mandatory)][string]$Archive,[Parameter(Mandatory)][string]$OutputDirectory)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
trap {Write-Output $_.ToString();Write-Output $_.ScriptStackTrace;throw $_}
$install=Join-Path '/tmp' ('lifecycle-'+[guid]::NewGuid().ToString('N'))
Expand-Archive $Archive $install
$manifest=Join-Path $install 'Webmania/Webmania.psd1'
Import-Module $manifest
Add-Type -Path (Join-Path $PSScriptRoot 'LifecycleFixture.cs')
$results=[Collections.Generic.List[object]]::new()
$privacy=[Collections.Generic.List[object]]::new()
$secret=ConvertTo-SecureString 'synthetic-lifecycle' -AsPlainText -Force
function Check([bool]$Condition,[string]$Name){if(-not $Condition){throw "Lifecycle assertion failed: $Name"}}
function Options($Server){
    $o=[Webmania.WebmaniaClientOptions]::new();$o.LoopbackTestEndpoint=$Server.Url;$o.Timeout=[timespan]::FromSeconds(6)
    if($null -ne $Server.Root){$o.LoopbackTestRootCertificate=$Server.Root};return $o
}
function Client($Server,[string]$Scope){
    $o=Options $Server
    if($Scope -eq 'company'){return New-WebmaniaCompanyClient -ConsumerKey $secret -ConsumerSecret $secret -AccessToken $secret -AccessTokenSecret $secret -Options $o}
    return New-WebmaniaMonitorClient -Bearer $secret -Options $o
}
$server=[IndependentServer]::new($true);$client=Client $server 'monitor'
try{
    $marker='PRIVATE-BINDER-INPUT-MARKER'
    $catalog=Get-Content (Join-Path $install 'Webmania/commands.json') -Raw|ConvertFrom-Json
    foreach($entry in $catalog){
        $caught=$null;try{& $entry.command -Client $client -Parameters $marker -Debug}catch{$caught=$_}
        Check ($null -ne $caught) "invalid DTO binder $($entry.command) rejected"
        $text=$caught.ToString()+$caught.Exception.ToString()+($caught|Out-String)+($caught.InvocationInfo|Format-List * -Force|Out-String)
        if($privacy.Count -eq 0){$text+=(Get-Error -InputObject $caught|Out-String)}
        Check (-not $text.Contains($marker)) "private DTO text $($entry.command) absent"
        Check ($text.Contains('[protected-invalid-input]')) "safe sentinel $($entry.command)"
        Check ($null -eq $caught.TargetObject) 'binder has no target'
        $privacy.Add(@{command=$entry.command;parameter='Parameters';errorId=$caught.FullyQualifiedErrorId;message=$caught.Exception.Message;privateMarkerAbsent=$true})
    }
    foreach($command in (Get-Command -Module Webmania)){
        foreach($parameter in $command.Parameters.Values){
            if($parameter.Name -in @('Verbose','Debug','ErrorAction','WarningAction','InformationAction','ProgressAction','ErrorVariable','WarningVariable','InformationVariable','OutVariable','OutBuffer','PipelineVariable')){continue}
            if($parameter.ParameterType -notin @([Security.SecureString],[Webmania.WebmaniaClientOptions],[Webmania.WebmaniaClient],[Webmania.PollOptions],[Threading.CancellationToken],[int],[Webmania.FileResult],[type],[Management.Automation.SwitchParameter])){continue}
            $arguments=@{};$arguments[$parameter.Name]=$marker
            # Guard runs before mandatory-parameter completion. Noninteractive
            # invocation avoids prompts when testing another required binder.
            $caught=$null;try{& $command.Name @arguments -Debug}catch{$caught=$_}
            Check ($null -ne $caught) "typed binder $($command.Name).$($parameter.Name) rejects"
            $text=$caught.ToString()+$caught.Exception.ToString()+($caught|Out-String)+($caught.InvocationInfo|Format-List * -Force|Out-String)
            Check (-not $text.Contains($marker)) "private typed text $($command.Name).$($parameter.Name) absent"
            $privacy.Add(@{command=$command.Name;parameter=$parameter.Name;errorId=$caught.FullyQualifiedErrorId;message=$caught.Exception.Message;privateMarkerAbsent=$true})
        }
    }
    Check ($server.Count -eq 0) 'all binder privacy probes zero I/O'
}finally{$client.Dispose();$server.Dispose()}

$cases=@(
    @{name='operation-http';tls=$false;scope='company';kind='operation'},
    @{name='operation-tls';tls=$true;scope='company';kind='operation'},
    @{name='mutation-tls';tls=$true;scope='monitor';kind='mutation'},
    @{name='company-page-fetch';tls=$true;scope='monitor';kind='companies'},
    @{name='municipality-page-fetch';tls=$true;scope='monitor';kind='municipalities'},
    @{name='report-page-fetch';tls=$true;scope='monitor';kind='reports'},
    @{name='report-held-request';tls=$true;scope='company';kind='report-hold'},
    @{name='report-delay';tls=$true;scope='company';kind='report-delay'},
    @{name='import-held';tls=$true;scope='monitor';kind='import'},
    @{name='import-delay';tls=$true;scope='monitor';kind='import-delay'},
    @{name='batch-company-fetch';tls=$true;scope='monitor';kind='batch-companies'},
    @{name='batch-municipality-fetch';tls=$true;scope='monitor';kind='batch-municipalities'},
    @{name='batch-report-fetch';tls=$true;scope='monitor';kind='batch-reports'}
)
$script=@'
param($manifest,$client,$kind,$items)
Import-Module $manifest
switch($kind){
 'operation'{Get-WebmaniaNfeCertificateValidity -Client $client -Parameters ([Webmania.NfeGetCertificateValidityParameters]::new())}
 'mutation'{
   $p=[Text.Json.JsonSerializer]::Deserialize('{"body":{"cnpj":"00000000000000","razao_social":"Synthetic","cep":"01001000","certificado_base64":"PHRlc3QvPg==","certificado_senha":"synthetic"}}',[Webmania.MonitorCreateCompanyParameters],[Webmania.WebmaniaJson]::Options)
   New-WebmaniaMonitorCompany -Client $client -Parameters $p
 }
 'import' {
   $p=[Webmania.MonitorGetImportStatusParameters]::new();$p.Uuid=[Webmania.Optional[string]]::Of('00000000-0000-4000-8000-000000000001')
   Wait-WebmaniaMonitorImport -Client $client -Parameters $p
 }
 'import-delay' {
   $p=[Webmania.MonitorGetImportStatusParameters]::new();$p.Uuid=[Webmania.Optional[string]]::Of('00000000-0000-4000-8000-000000000001')
   Wait-WebmaniaMonitorImport -Client $client -Parameters $p
 }
 'batch-companies'{Read-WebmaniaMonitorCompanyBatch -Client $client -Parameters ([Webmania.MonitorListCompaniesParameters]::new()) -MaximumItems 2 -MaximumPages 3|ForEach-Object {$items.Enqueue($_)}}
 'batch-municipalities'{
   $p=[Webmania.MonitorListCompanyMunicipalitiesParameters]::new();$p.Company=[Webmania.Optional[string]]::Of('00000000-0000-4000-8000-000000000001')
   Read-WebmaniaMonitorCompanyMunicipalityBatch -Client $client -Parameters $p -MaximumItems 2 -MaximumPages 3|ForEach-Object {$items.Enqueue($_)}
 }
 'batch-reports'{Read-WebmaniaMonitorReportBatch -Client $client -Parameters ([Webmania.MonitorListReportsParameters]::new()) -MaximumItems 2 -MaximumPages 3|ForEach-Object {$items.Enqueue($_)}}
 'companies'{Get-WebmaniaMonitorCompanyItem -Client $client -Parameters ([Webmania.MonitorListCompaniesParameters]::new()) -MaximumPages 3|ForEach-Object {$items.Enqueue($_)}}
 'municipalities'{
   $p=[Webmania.MonitorListCompanyMunicipalitiesParameters]::new();$p.Company=[Webmania.Optional[string]]::Of('00000000-0000-4000-8000-000000000001')
   Get-WebmaniaMonitorCompanyMunicipalityItem -Client $client -Parameters $p -MaximumPages 3|ForEach-Object {$items.Enqueue($_)}
 }
 'reports'{Get-WebmaniaMonitorReportItem -Client $client -Parameters ([Webmania.MonitorListReportsParameters]::new()) -MaximumPages 3|ForEach-Object {$items.Enqueue($_)}}
 default{
   $p=[Text.Json.JsonSerializer]::Deserialize('{"body":{"modelo":"nfe","relatorio":"danfe","numero_inicio":"1","numero_final":"5"}}',[Webmania.FiscalCreateOrPollReportParameters],[Webmania.WebmaniaJson]::Options)
   $o=[Webmania.PollOptions]::new();$o.MaximumAttempts=5;$o.Deadline=[timespan]::FromSeconds(15)
   Wait-WebmaniaFiscalReport -Client $client -Parameters $p -Options $o
 }
}
'@
foreach($case in $cases){
    $server=[IndependentServer]::new($case.tls);$client=Client $server $case.scope;$ps=[powershell]::Create()
    $items=[Collections.Concurrent.ConcurrentQueue[object]]::new()
    try{
        $expectedRequests=1;$expectedItems=0
        switch($case.kind){
            'companies'{$item='{"uuid":"00000000-0000-4000-8000-000000000001"}';$expectedRequests=2;$expectedItems=1}
            'municipalities'{$item='{"uuid":"00000000-0000-4000-8000-000000000001","tipo_download":1,"municipio":"Synthetic","uf":"SP","codigo_ibge":"3550308"}';$expectedRequests=2;$expectedItems=1}
            'reports'{$item='{"uuid":"00000000-0000-4000-8000-000000000001","relatorio":"xml","modelo":"nfe","status":"concluido"}';$expectedRequests=2;$expectedItems=1}
        }
        if($case.kind -like 'batch-*'){
            $expectedRequests=2
            $item=switch($case.kind){
                'batch-companies'{'{"uuid":"00000000-0000-4000-8000-000000000001"}'}
                'batch-municipalities'{'{"uuid":"00000000-0000-4000-8000-000000000001","tipo_download":1,"municipio":"Synthetic","uf":"SP","codigo_ibge":"3550308"}'}
                'batch-reports'{'{"uuid":"00000000-0000-4000-8000-000000000001","relatorio":"xml","modelo":"nfe","status":"concluido"}'}
            }
            $server.Enqueue([IndependentReply]@{Body=('{"data":['+$item+'],"meta":{"current_page":1,"last_page":2,"per_page":10,"total":2}}')})
        }
        if($expectedItems){$server.Enqueue([IndependentReply]@{Body=('{"data":['+$item+'],"meta":{"current_page":1,"last_page":2,"per_page":10,"total":2}}')})}
        if($case.kind -eq 'report-delay'){$server.Enqueue([IndependentReply]@{Body='{"uuid":"000000000000000000000000000000000000","status":"processando"}'})}
        elseif($case.kind -eq 'import-delay'){$server.Enqueue([IndependentReply]@{Body='{"uuid":"00000000-0000-4000-8000-000000000001","status":"processando","processado":0,"importados":[],"descartados":[]}'})}
        else{$server.Enqueue([IndependentReply]@{Hold=$true})}
        $null=$ps.AddScript($script).AddArgument($manifest).AddArgument($client).AddArgument($case.kind).AddArgument($items)
        $invoke=$ps.BeginInvoke();$arrived=$server.WaitCount($expectedRequests,4000)
        if(-not $arrived){$ps.Streams.Error|ForEach-Object {Write-Output $_.Exception.ToString()}}
        Check $arrived "$($case.name) request arrived"
        if($case.kind -in @('report-delay','import-delay')){[Threading.Thread]::Sleep(150)}
        $watch=[Diagnostics.Stopwatch]::StartNew();$stopping=$ps.BeginStop($null,$null)
        $completed=$stopping.AsyncWaitHandle.WaitOne(700)
        $exception='';try{$ps.EndStop($stopping);$null=$ps.EndInvoke($invoke)}catch{$exception=$_.Exception.GetType().FullName}
        $elapsed=$watch.ElapsedMilliseconds
        if($case.kind -notin @('report-delay','import-delay')){
            $closeWatch=[Diagnostics.Stopwatch]::StartNew()
            while($server.Requests[-1].ClosedMs -lt 0 -and $closeWatch.ElapsedMilliseconds -lt 200){[Threading.Thread]::Sleep(5)}
            Check ($server.Requests[-1].ClosedMs -ge 0) "$($case.name) held socket closed"
        }
        Check ($completed -and $elapsed -lt 900) "$($case.name) native stop prompt"
        Check ($server.Count -eq $expectedRequests -and $items.Count -eq $expectedItems) "$($case.name) no retry and partial items retained"
        # Stopping one invocation must not dispose or poison its shared client.
        if($case.scope -eq 'company'){$server.Enqueue([IndependentReply]@{Body='{"expiration":1}'});Get-WebmaniaNfeCertificateValidity -Client $client -Parameters ([Webmania.NfeGetCertificateValidityParameters]::new())|Out-Null}
        else{$server.Enqueue([IndependentReply]@{Body='{"data":[],"meta":{"current_page":1,"last_page":1,"per_page":10,"total":0}}'});Get-WebmaniaMonitorCompanies -Client $client -Parameters ([Webmania.MonitorListCompaniesParameters]::new())|Out-Null}
        $results.Add(@{case=$case.name;nativeStop=$true;stopElapsedMs=$elapsed;stopCompleted=$completed;requestCountBeforeReuse=$expectedRequests;requestCountAfterReuse=$server.Count;partialItems=$items.Count;endException=$exception;requests=$server.Requests;pass=$true})
    }finally{$ps.Dispose();$client.Dispose();$server.Dispose()}
}
# Explicit cancellation retains SDK outcome context; AsTask is caller-owned.
$server=[IndependentServer]::new($true);$client=Client $server 'monitor';$cts=[Threading.CancellationTokenSource]::new()
try{
    $p=[Text.Json.JsonSerializer]::Deserialize('{"body":{"cnpj":"00000000000000","razao_social":"Synthetic","cep":"01001000","certificado_base64":"PHRlc3QvPg==","certificado_senha":"synthetic"}}',[Webmania.MonitorCreateCompanyParameters],[Webmania.WebmaniaJson]::Options)
    $cts.Cancel();$before=$server.Count;$caught=$null
    try{New-WebmaniaMonitorCompany -Client $client -Parameters $p -CancellationToken $cts.Token}catch{$caught=$_}
    Check ($caught.Exception.Kind -eq 'cancelled' -and $server.Count -eq $before) 'caller pre-cancel zero I/O'
    $cts.Dispose();$cts=[Threading.CancellationTokenSource]::new()
    $server.Enqueue([IndependentReply]@{Hold=$true})
    $task=New-WebmaniaMonitorCompany -Client $client -Parameters $p -CancellationToken $cts.Token -AsTask
    Check ($server.WaitCount(1,4000)) 'AsTask mutation arrived';[Threading.Thread]::Sleep(100)
    Check (-not $task.IsCompleted) 'AsTask survives command lifetime'
    $watch=[Diagnostics.Stopwatch]::StartNew();$cts.Cancel();$caught=$null
    try{$task.GetAwaiter().GetResult()}catch{$caught=$_}
    $native=$caught.Exception;while($null -ne $native -and $native -isnot [Webmania.WebmaniaCancellationException]){$native=$native.InnerException}
    Check ($task.IsCanceled -and $native -is [OperationCanceledException]) 'AsTask retains native canceled Task semantics'
    Check ($native.CancellationToken -eq $cts.Token) 'AsTask preserves exact original caller cancellation token'
    Check ($null -eq $native.InnerException -and $null -eq $native.Diagnostic.InnerException) 'native cancellation diagnostic has no raw inner cause'
    $sdk=$native.Diagnostic
    Check ($null -ne $sdk -and $sdk.Kind -eq 'cancelled' -and $sdk.OutcomeUncertain) 'AsTask cancellation preserves uncertainty'
    Check ($watch.ElapsedMilliseconds -lt 700) 'explicit caller cancellation prompt'
    $results.Add(@{case='caller-owned-AsTask-explicit-cancellation';pass=$true;elapsedMs=$watch.ElapsedMilliseconds;kind=$sdk.Kind;outcomeUncertain=$sdk.OutcomeUncertain;requests=$server.Requests})
    $cts.Dispose();$cts=[Threading.CancellationTokenSource]::new();$server.Enqueue([IndependentReply]@{Hold=$true})
    $cancelTask=[LifecycleCancellation]::AfterRequest($server,$cts,2);$watch=[Diagnostics.Stopwatch]::StartNew();$caught=$null
    try{New-WebmaniaMonitorCompany -Client $client -Parameters $p -CancellationToken $cts.Token}catch{$caught=$_}
    $null=$cancelTask.GetAwaiter().GetResult()
    Check ($null -ne $caught -and $caught.Exception -is [Webmania.WebmaniaException] -and $caught.Exception.Kind -eq 'cancelled' -and $caught.Exception.OutcomeUncertain) 'linked synchronous caller cancellation retains typed uncertainty'
    $cancelCompletion=[Diagnostics.Stopwatch]::GetElapsedTime([LifecycleCancellation]::CancellationTimestamp).TotalMilliseconds
    Check ($server.Count -eq 2 -and $cancelCompletion -lt 700) 'linked synchronous cancellation prompt with one request'
    $results.Add(@{case='linked-sync-caller-cancellation';pass=$true;elapsedMs=$watch.ElapsedMilliseconds;cancellationCompletionMs=$cancelCompletion;kind=$caught.Exception.Kind;outcomeUncertain=$caught.Exception.OutcomeUncertain;requests=$server.Requests[-1]})
}finally{$cts.Dispose();$client.Dispose();$server.Dispose()}
ConvertTo-Json -InputObject @($privacy) -Depth 8|Set-Content (Join-Path $OutputDirectory 'binder-privacy.json')
ConvertTo-Json -InputObject @($results) -Depth 12|Set-Content (Join-Path $OutputDirectory 'lifecycle-results.json')
Write-Output "PASS: $($privacy.Count) protected binder cases with zero I/O; $($cases.Count) native stop cases; caller-owned task/cancellation controls"
