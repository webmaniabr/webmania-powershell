$n=New-WebmaniaJsonNumber -Text '9223372036854775808'
Assert ($n.Text -eq '9223372036854775808') 'number helper preserves greater-than-Int64 text'
$present=New-WebmaniaOptional -Type ([Webmania.JsonNumber]) -Value $n
$omitted=New-WebmaniaOptional -Type ([string]) -Omitted
$nullValue=New-WebmaniaOptional -Type ([string]) -Null
$falseValue=New-WebmaniaOptional -Type ([bool]) -Value $false
Assert ($present.IsSet -and $present.Value.Text -eq $n.Text) 'typed Optional present exact number'
Assert (-not $omitted.IsSet -and $nullValue.IsSet -and $nullValue.IsNull -and $falseValue.IsSet -and -not $falseValue.Value) 'omission explicit null false preserved'
Reject 'Optional wrong value type' {New-WebmaniaOptional -Type ([string]) -Value 42} 'LocalValidation'|Out-Null
Assert (@(Get-WebmaniaOperation|Where-Object {-not $_.Enabled}).Count -eq 1) 'blocked operation discoverable'
$modelTypes=@{}
foreach($type in [Webmania.WebmaniaClient].Assembly.GetExportedTypes()){
    $source=[Attribute]::GetCustomAttribute($type,[Webmania.SchemaSourceAttribute])
    if($null -ne $source){$modelTypes[$source.Module+'|'+$source.Pointer]=$type}
}
$schemaDocument=[Text.Json.JsonDocument]::Parse([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'fixtures/schema-cases.json')))
$roundtrips=0
try{
    foreach($case in $schemaDocument.RootElement.EnumerateArray()){
        if(-not $case.GetProperty('valid').GetBoolean()){continue}
        $schema=[Text.Json.JsonElement]::new()
        if(-not $case.TryGetProperty('schema',[ref]$schema)){continue}
        $key=$case.GetProperty('module').GetString()+'|#/components/schemas/'+$schema.GetString()
        if(-not $modelTypes.ContainsKey($key)){continue}
        $instance=$case.GetProperty('instance');$type=$modelTypes[$key]
        $dto=[Text.Json.JsonSerializer]::Deserialize($instance.GetRawText(),$type,[Webmania.WebmaniaJson]::Options)
        $restored=[Text.Json.JsonSerializer]::SerializeToElement($dto,$type,[Webmania.WebmaniaJson]::Options)
        Assert ([Text.Json.JsonElement]::DeepEquals($instance,$restored)) "public DTO pinned schema roundtrip $key case=$roundtrips"
        $roundtrips++
    }
}finally{$schemaDocument.Dispose()}
Assert ($roundtrips -gt 100) "typed model schema cases exercised ($roundtrips)"
$server=[PsSocketFixture]::new($true)
$o=[Webmania.WebmaniaClientOptions]::new();$o.LoopbackTestEndpoint=[uri]"https://localhost:$($server.Port)/";$o.Timeout=[timespan]::FromSeconds(5)
$o.LoopbackTestRootCertificate=[Security.Cryptography.X509Certificates.X509CertificateLoader]::LoadCertificate($server.CertificateDer)
$monitor=New-ScopedClient 'monitor' 'company' $o;$company=New-ScopedClient 'company' 'company' $o;$files=New-ScopedClient 'api1-files' 'company' $o
try{
    $server.Json('{"data":[],"meta":{"current_page":1,"last_page":1,"per_page":10,"total":0}}')
    $p=[Webmania.MonitorListCompaniesParameters]::new()
    $task=Get-WebmaniaMonitorCompanies -Client $monitor -Parameters $p -AsTask
    Assert ($task -is [Threading.Tasks.Task[Webmania.ApiResponse[Webmania.Api2MonitorReadsMonitorCompanyPage]]]) 'AsTask preserves native typed task'
    $r=$task.GetAwaiter().GetResult()
    Assert (-not $server.Requests.ToArray()[-1].Target.Contains('?')) 'omitted query stays omitted'
    Assert ($r.Data.Meta.Value.PerPage.Value.Text -eq '10') 'typed nested exact response numbers'
    $p.Page=New-WebmaniaOptional -Type ([Webmania.JsonNumber]) -Value (New-WebmaniaJsonNumber -Text '1e0')
    Get-WebmaniaMonitorCompanies -Client $monitor -Parameters $p|Out-Null
    Assert ($server.Requests.ToArray()[-1].Target.Contains('page=1e0')) 'exact exponent wire representation preserved'
    $p.Page=[Webmania.Optional[Webmania.JsonNumber]]::Null
    $before=$server.Requests.Count
    Reject 'explicit null query rejected' {Get-WebmaniaMonitorCompanies -Client $monitor -Parameters $p} 'validation'|Out-Null
    $p=[Webmania.MonitorListCompaniesParameters]::new()
    $p.Extras.Add('page',[Text.Json.JsonDocument]::Parse('1').RootElement.Clone())
    Reject 'extension collision' {Get-WebmaniaMonitorCompanies -Client $monitor -Parameters $p} 'validation'|Out-Null
    Assert ($server.Requests.Count -eq $before) 'null and collision zero network'
    $invalidOptions=[Webmania.WebmaniaClientOptions]::new();$invalidOptions.Timeout=[timespan]::Zero
    Reject 'invalid client limits' {New-WebmaniaMonitorClient -Bearer $secure.monitor -Options $invalidOptions} 'LocalValidation'|Out-Null
    $anonymous=New-ScopedClient 'api2-files' 'anonymous' $o
    try{
        $entry=$catalog|Where-Object operationId -eq 'fileGetMdfeXml';$mdfeFile=TypedInput $entry $byId[$entry.operationId]
        Reject 'MDF-e anonymous forbidden' {Get-WebmaniaFileMdfeXml -Client $anonymous -Parameters $mdfeFile} 'credential_scope'|Out-Null
    }finally{$anonymous.Dispose()}
    Assert ($server.Requests.Count -eq $before) 'invalid options and unsupported file auth zero network'
    $p=[Webmania.MonitorListCompaniesParameters]::new()
    $cts=[Threading.CancellationTokenSource]::new();$cts.Cancel()
    try{Reject 'pre-cancelled operation' {Get-WebmaniaMonitorCompanies -Client $monitor -Parameters $p -CancellationToken $cts.Token} 'cancelled'|Out-Null}finally{$cts.Dispose()}
    Assert ($server.Requests.Count -eq $before) 'pre-cancelled operation zero network'
    $server.Json('{"data":[{"uuid":"00000000-0000-4000-8000-000000000001","razao_social":"Synthetic"}],"meta":{"current_page":1,"last_page":1,"per_page":10,"total":1}}')
    $items=@(Get-WebmaniaMonitorCompanyItem -Client $monitor -Parameters $p -MaximumPages 1)
    Assert ($items.Count -eq 1 -and $items[0] -is [Webmania.Api2MonitorReadsMonitorCompany]) "company pagination emits typed item (count=$($items.Count); types=$(($items|ForEach-Object {$_.GetType().FullName}) -join ','))"
    $server.Json('{"data":[{"uuid":"00000000-0000-4000-8000-000000000001","tipo_download":1,"municipio":"Synthetic","uf":"SP","codigo_ibge":"3550308"}],"meta":{"current_page":1,"last_page":1,"per_page":10,"total":1}}')
    $municipality=[Webmania.MonitorListCompanyMunicipalitiesParameters]::new();$municipality.Company=[Webmania.Optional[string]]::Of('00000000-0000-4000-8000-000000000001')
    $items=@(Get-WebmaniaMonitorCompanyMunicipalityItem -Client $monitor -Parameters $municipality -MaximumPages 1)
    Assert ($items.Count -eq 1 -and $items[0] -is [Webmania.Api2MonitorReadsMonitorMunicipalityRegistration]) 'municipality pagination emits typed item'
    $server.Json('{"data":[{"uuid":"00000000-0000-4000-8000-000000000001","relatorio":"xml","modelo":"nfe","status":"concluido"}],"meta":{"current_page":1,"last_page":1,"per_page":10,"total":1}}')
    $report=[Webmania.MonitorListReportsParameters]::new()
    $items=@(Get-WebmaniaMonitorReportItem -Client $monitor -Parameters $report -MaximumPages 1)
    Assert ($items.Count -eq 1 -and $items[0] -is [Webmania.Api2MonitorDocumentsMonitorReport]) 'report pagination emits typed item'
    $server.Json('{"data":[],"meta":{"current_page":1,"last_page":2,"per_page":10,"total":0}}')
    $before=$server.Requests.Count
    Reject 'bounded pagination stops' {Get-WebmaniaMonitorCompanyItem -Client $monitor -Parameters $p -MaximumPages 1} 'page_limit'|Out-Null
    Assert ($server.Requests.Count -eq $before+1) 'bounded pagination makes one page request'
    $server.Json('{"data":[],"meta":{"current_page":2,"last_page":2,"per_page":10,"total":0}}')
    Reject 'nonadvancing pagination rejects' {Get-WebmaniaMonitorCompanyItem -Client $monitor -Parameters $p -MaximumPages 2} 'protocol'|Out-Null
    $entry=$catalog|Where-Object operationId -eq 'fiscalCreateOrPollReport';$params=TypedInput $entry $byId[$entry.operationId]
    $poll=[Webmania.PollOptions]::new();$poll.MaximumAttempts=1;$poll.Deadline=[timespan]::FromSeconds(5)
    $server.Json('{"uuid":"000000000000000000000000000000000000","status":"concluido"}')
    $r=Wait-WebmaniaFiscalReport -Client $company -Parameters $params -Options $poll
    Assert ($r -is [Webmania.ApiResponse[Webmania.FiscalCreateOrPollReportResult]]) 'report waiter typed success'
    $server.Json('{"uuid":"000000000000000000000000000000000000","status":"processando"}')
    $before=$server.Requests.Count
    $failure=Reject 'report attempt bound' {Wait-WebmaniaFiscalReport -Client $company -Parameters $params -Options $poll} 'poll_limit'
    Assert ($server.Requests.Count -eq $before+1 -and $failure.Exception.OutcomeUncertain) 'bounded waiter retains uncertainty without replay'
    $poll.Interval=[timespan]::FromSeconds(1);$before=$server.Requests.Count
    Reject 'invalid polling interval' {Wait-WebmaniaFiscalReport -Client $company -Parameters $params -Options $poll} 'validation'|Out-Null
    Assert ($server.Requests.Count -eq $before) 'invalid polling option zero network'
    $lookup=[Webmania.NfeGetDocumentParameters]::new();$lookup.ID=[Webmania.Optional[string]]::Of('PS-UNION-1')
    $server.Json('{"uuid":"00000000-0000-4000-8000-000000000001","status":"future_state","future":false}')
    $r=Get-WebmaniaNfeDocument -Client $company -Parameters $lookup
    Assert ($r.Data.AsVariant1().AsVariant1().Status.Value -eq 'future_state') 'nested typed response union and unknown status preserved'
    Assert ($r.Data.AsVariant1().AsVariant1().Extras['future'].GetBoolean() -eq $false) 'unknown response extension false preserved'
    $server.Json('{"message":"synthetic-key synthetic-secret synthetic-access PS-UNION-1 https://example.test/?token=hidden"}',401)
    $before=$server.Requests.Count
    $failure=Reject 'protected 401 no retry' {Get-WebmaniaNfeDocument -Client $company -Parameters $lookup} 'http'
    $diagnostic=$failure.ToString()+$failure.Exception.ToString()+[Text.Json.JsonSerializer]::Serialize($failure.Exception,[Webmania.WebmaniaException],[Webmania.WebmaniaJson]::Options)
    Assert ($diagnostic -notmatch 'synthetic-key|synthetic-secret|synthetic-access|PS-UNION-1|hidden') 'protected error never exposes credentials selector URL'
    Assert ($server.Requests.Count -eq $before+1 -and $null -eq $failure.Exception.InnerException -and $null -eq $failure.TargetObject) '401 single request safe error record'
    $entry=$catalog|Where-Object operationId -eq 'monitorCreateCompany';$params=TypedInput $entry $byId[$entry.operationId]
    $server.Json('{"message":"temporary synthetic-monitor"}',503);$before=$server.Requests.Count
    $failure=Reject 'mutation error no retry' {New-WebmaniaMonitorCompany -Client $monitor -Parameters $params} 'http'
    Assert ($failure.Exception.OutcomeUncertain -and $server.Requests.Count -eq $before+1) 'mutation uncertainty retained'
    $entry=$catalog|Where-Object operationId -eq 'nfeDownloadDanfe';$params=TypedInput $entry $byId[$entry.operationId]
    $server.File('application/pdf');$file=Receive-WebmaniaNfeDanfe -Client $files -Parameters $params
    $path=Join-Path $OutputDirectory 'synthetic.pdf';$saved=$file|Save-WebmaniaFile -LiteralPath $path
    Assert ($saved.Length -eq $file.Bytes.Length) 'validated file saved intact'
    Reject 'file overwrite guarded' {$file|Save-WebmaniaFile -LiteralPath $path} 'LocalValidation'|Out-Null
    $file|Save-WebmaniaFile -LiteralPath $path -Force|Out-Null
    $server.Body=[Text.Encoding]::UTF8.GetBytes('<html>processing</html>');$server.Media='text/html'
    Reject 'undeclared HTML success is rejected' {Receive-WebmaniaNfeDanfe -Client $files -Parameters $params} 'protocol'|Out-Null
    $server.Json('{}')
    $nonfile=Receive-WebmaniaNfeDanfe -Client $files -Parameters $params
    Assert (-not $nonfile.IsFile -and $nonfile.Representation -eq [Webmania.FileRepresentation]::Json) 'declared JSON is a distinct nonfile result'
    Reject 'nonfile never saved as PDF' {$nonfile|Save-WebmaniaFile -LiteralPath (Join-Path $OutputDirectory 'bad.pdf')} 'LocalValidation'|Out-Null
    Assert (-not (Test-Path (Join-Path $OutputDirectory 'bad.pdf'))) 'rejected nonfile creates no output'
    $server.Media='application/pdf';$server.Body=[Text.Encoding]::UTF8.GetBytes('bad pdf');$before=$server.Requests.Count
    Reject 'invalid PDF detected' {Receive-WebmaniaNfeDanfe -Client $files -Parameters $params} 'protocol'|Out-Null
    Assert ($server.Requests.Count -eq $before+1) 'invalid file not replayed'
    $reportClient=New-ScopedClient 'report-file' 'capability' $o
    try{
        $entry=$catalog|Where-Object operationId -eq 'fiscalDownloadReport';$reportFile=TypedInput $entry $byId[$entry.operationId]
        foreach($media in @('application/pdf','application/zip','text/csv','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')){
            $server.File($media)
            $result=Receive-WebmaniaFiscalReport -Client $reportClient -Parameters $reportFile
            Assert ($result.IsFile -and [Convert]::ToBase64String($result.Bytes.ToArray()) -eq [Convert]::ToBase64String($server.Body)) "report media bytes $media"
        }
    }finally{$reportClient.Dispose()}
    $limitedOptions=[Webmania.WebmaniaClientOptions]::new();$limitedOptions.LoopbackTestEndpoint=$o.LoopbackTestEndpoint;$limitedOptions.LoopbackTestRootCertificate=$o.LoopbackTestRootCertificate;$limitedOptions.MaximumResponseBytes=8
    $limited=New-ScopedClient 'monitor' 'company' $limitedOptions
    try{
        $server.Json('{"data":[],"meta":{"current_page":1,"last_page":1,"per_page":10,"total":0}}');$before=$server.Requests.Count
        Reject 'response bound' {Get-WebmaniaMonitorCompanies -Client $limited -Parameters ([Webmania.MonitorListCompaniesParameters]::new())} 'response_limit'|Out-Null
        Assert ($server.Requests.Count -eq $before+1) 'response bound no replay'
    }finally{$limited.Dispose()}
    $limitedOptions.MaximumResponseBytes=16384;$limitedOptions.MaximumRequestBytes=1
    $limited=New-ScopedClient 'monitor' 'company' $limitedOptions
    try{
        $entry=$catalog|Where-Object operationId -eq 'monitorCreateCompany';$oversize=TypedInput $entry $byId[$entry.operationId];$before=$server.Requests.Count
        Reject 'request bound' {New-WebmaniaMonitorCompany -Client $limited -Parameters $oversize} 'request_limit'|Out-Null
        Assert ($server.Requests.Count -eq $before) 'request bound zero network'
    }finally{$limited.Dispose()}
    Assert ($server.Errors.Count -eq 0) 'regression TLS fixture errors absent'
    @{requests=$server.Requests.ToArray();allCredentialsSynthetic=$true}|ConvertTo-Json -Depth 12|Set-Content (Join-Path $OutputDirectory 'regression-requests.json')
}finally{$monitor.Dispose();$company.Dispose();$files.Dispose();$server.Dispose()}
