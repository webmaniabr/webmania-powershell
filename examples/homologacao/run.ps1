# Exemplo neutro de homologação (ambiente 2) com o módulo PowerShell.
# Lê a configuração somente de variáveis WEBMANIA_*, imprime uma linha JSON mascarada por passo
# e nunca repete uma mutação. Sem WEBMANIA_LIVE=1 não importa o módulo nem faz requisições (saída 77). Os escopos
# nfe, nfse e all exigem WEBMANIA_LIVE_LEDGER gravável; sem ele também sai com 77 antes de qualquer requisição.
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$PollAttempts=24
$PollSeconds=5
$script:failed=0

function Env([string]$Name){$value=[Environment]::GetEnvironmentVariable($Name);if([string]::IsNullOrEmpty($value)){$null}else{$value}}
function Out-Line($Value){[Console]::Out.WriteLine(($Value|ConvertTo-Json -Compress -Depth 4))}
function Block([string]$Reason){
    if($Reason){Out-Line ([ordered]@{result='blocked';reason=$Reason})}else{[Console]::Out.WriteLine('{"result":"blocked"}')}
    exit 77
}
function Ref([string]$Value){
    if([string]::IsNullOrEmpty($Value)){return $null}
    [Convert]::ToHexStringLower([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($Value))).Substring(0,12)
}
function Emit([string]$Step,[string]$Operation,[bool]$Ok,$Status=$null,[string]$Outcome=$null,[string]$Kind=$null,[string]$Reference=$null,$File=$null){
    if(-not $Ok){$script:failed++}
    $line=[ordered]@{step=$Step;operation=$Operation;ok=$Ok;http_status=$Status;outcome=$(if($Outcome){$Outcome}else{$null});kind=$(if($Kind){$Kind}else{$null});ref=$(if($Reference){$Reference}else{$null})}
    if($null -ne $File){$line.file=$File}
    Out-Line $line
}
function Ledger([string]$Model,[string]$Identifier,[string]$Status,[string]$Operation){
    $path=Env 'WEBMANIA_LIVE_LEDGER'
    if(-not $path -or [string]::IsNullOrEmpty($Identifier)){return}
    [IO.File]::AppendAllText($path,(([ordered]@{model=$Model;identifier=$Identifier;status=$Status;operation=$Operation})|ConvertTo-Json -Compress)+"`n")
}
function FileSummary([Webmania.FileResult]$File){
    if($null -ne $File.RedirectLocation){return [ordered]@{redirect=$true}}
    $bytes=$File.Bytes.ToArray()
    $head=[Text.Encoding]::UTF8.GetString($bytes,0,[Math]::Min($bytes.Length,64)).TrimStart([char]0xFEFF,' ',"`t","`r","`n")
    $format=if($bytes.Length -ge 5 -and [Text.Encoding]::ASCII.GetString($bytes,0,5) -eq '%PDF-'){'pdf'}elseif($bytes.Length -ge 2 -and $bytes[0] -eq 0x50 -and $bytes[1] -eq 0x4B){'zip'}elseif($head.StartsWith('<')){'xml'}else{'other'}
    [ordered]@{size=$bytes.Length;sha256=[Convert]::ToHexStringLower([Security.Cryptography.SHA256]::HashData($bytes));format=$format}
}
function Fields([Text.Json.JsonElement]$Json){if($Json.ValueKind -eq [Text.Json.JsonValueKind]::Array -and $Json.GetArrayLength() -gt 0){$Json[0]}else{$Json}}
function Text($Json,[string]$Name){
    $value=[Text.Json.JsonElement]::new()
    if($null -ne $Json -and $Json.ValueKind -eq [Text.Json.JsonValueKind]::Object -and $Json.TryGetProperty($Name,[ref]$value) -and $value.ValueKind -eq [Text.Json.JsonValueKind]::String){$value.GetString()}else{''}
}
# Typed DTOs come from exact JSON text; a payload node is embedded verbatim (numbers stay exact).
function Params([type]$Type,[string]$Json){[Text.Json.JsonSerializer]::Deserialize($Json,$Type,[Webmania.WebmaniaJson]::Options)}
function Json($Value){$Value|ConvertTo-Json -Compress -Depth 8}
class UnknownOutcome : Exception {}

# Runs one step; a sent mutation whose outcome is unknown stops the whole run.
function Call([string]$Step,[string]$Operation,[scriptblock]$Action,[string]$Reference=$null,[switch]$Mutation){
    try{
        $result=& $Action
        if($result -is [Webmania.FileResult]){
            $usable=$result.IsFile -or $null -ne $result.RedirectLocation
            Emit $Step $Operation $usable $result.StatusCode -Kind $(if($usable){$null}else{$result.Representation.ToString()}) -Reference (Ref $Reference) -File (FileSummary $result)
        }else{Emit $Step $Operation $true 200 -Reference (Ref $Reference)}
        return ,$result
    }catch{
        $error0=$_.Exception
        if($error0 -is [Webmania.WebmaniaException]){
            Emit $Step $Operation $false $error0.StatusCode -Outcome $(if($error0.OutcomeUncertain){'unknown'}else{$null}) -Kind $error0.Kind -Reference (Ref $Reference)
            if($Mutation -and $error0.OutcomeUncertain){throw [UnknownOutcome]::new()}
        }else{Emit $Step $Operation $false -Kind 'local_validation' -Reference (Ref $Reference)}
        return $null
    }
}
function Poll([string]$Step,[string]$Operation,[scriptblock]$Fetch,[scriptblock]$Done,[string]$Reference){
    $last=$null
    for($attempt=0;$attempt -lt $PollAttempts;$attempt++){
        $response=Call $Step $Operation $Fetch $Reference
        if($null -ne $response){$last=Fields $response.Json;if(& $Done (Text $last 'status')){return ,$last}}
        if($attempt -lt $PollAttempts-1){Start-Sleep -Seconds $PollSeconds}
    }
    return ,$last
}
function Payload([string]$Name){
    $path=Env $Name
    if(-not $path -or -not [IO.File]::Exists($path)){return $null}
    $node=[Text.Json.Nodes.JsonNode]::Parse([IO.File]::ReadAllText($path))
    if($node -is [Text.Json.Nodes.JsonObject] -and $node['ambiente'] -is [Text.Json.Nodes.JsonValue] -and $node['ambiente'].GetValueKind() -eq [Text.Json.JsonValueKind]::Number -and $node['ambiente'].ToJsonString() -eq '2'){return ,$node}
    return $null
}
function Options([string]$Url){
    $uri=[Uri]::new($Url)
    $options=[Webmania.WebmaniaClientOptions]::new()
    # Plain HTTP is accepted only for a loopback test server (origin only).
    if($uri.Scheme -eq 'http' -and $uri.IsLoopback){$options.LoopbackTestEndpoint=[Uri]::new($uri.GetLeftPart([UriPartial]::Authority)+'/')}else{$options.ServiceEndpoint=$uri}
    $options
}
function Secret([string]$Name){ConvertTo-SecureString -String (Env $Name) -AsPlainText -Force}

if((Env 'WEBMANIA_LIVE') -ne '1'){Block $null}
$api1=if(Env 'WEBMANIA_API1_BASE_URL'){Env 'WEBMANIA_API1_BASE_URL'}else{'https://webmania.com.br/api'}
$filesBase=if(Env 'WEBMANIA_FILES_BASE_URL'){Env 'WEBMANIA_FILES_BASE_URL'}else{'https://nfe.webmania.com.br'}
$api2=if(Env 'WEBMANIA_API2_BASE_URL'){Env 'WEBMANIA_API2_BASE_URL'}else{'https://api.webmania.com.br'}
$scope=if(Env 'WEBMANIA_LIVE_SCOPE'){Env 'WEBMANIA_LIVE_SCOPE'}else{'readonly'}
if($scope -cnotin @('readonly','nfe','nfse','all')){Block 'scope'}
# The allow list is required: without it no origin is trusted (fail closed, before any credential).
$allowed=@("$(Env 'WEBMANIA_LIVE_ALLOWED_HOSTS')".Split(',',[StringSplitOptions]::RemoveEmptyEntries -bor [StringSplitOptions]::TrimEntries)|ForEach-Object {$_.ToLowerInvariant()})
if($allowed.Count -eq 0){Block 'allowed_hosts'}
foreach($url in @($api1,$filesBase,$api2)){$parsed=$null;if(-not [Uri]::TryCreate($url,[UriKind]::Absolute,[ref]$parsed) -or $parsed.Host.ToLowerInvariant() -notin $allowed){Block 'origin_not_allowed'}}
$names=@('WEBMANIA_CONSUMER_KEY','WEBMANIA_CONSUMER_SECRET','WEBMANIA_ACCESS_TOKEN','WEBMANIA_ACCESS_TOKEN_SECRET','WEBMANIA_ISSUER_TOKEN')
foreach($name in $names){if(-not (Env $name)){Block 'credentials'}}
$nfeDocument=if($scope -in @('nfe','all')){Payload 'WEBMANIA_LIVE_NFE_PAYLOAD'}else{$null}
$nfseDocument=if($scope -in @('nfse','all')){Payload 'WEBMANIA_LIVE_NFSE_PAYLOAD'}else{$null}
if(($scope -in @('nfe','all') -and $null -eq $nfeDocument) -or ($scope -in @('nfse','all') -and $null -eq $nfseDocument)){Block 'payload'}
if($null -ne $nfeDocument -or $null -ne $nfseDocument){
    # An unknown outcome is recorded only in the ledger: it must be writable before any mutation.
    $ledgerPath=Env 'WEBMANIA_LIVE_LEDGER'
    if(-not $ledgerPath){Block 'ledger'}
    $ledgerOptions=[IO.FileStreamOptions]@{Mode=[IO.FileMode]::Append;Access=[IO.FileAccess]::Write}
    if(-not $IsWindows){$ledgerOptions.UnixCreateMode=[IO.UnixFileMode]::UserRead -bor [IO.UnixFileMode]::UserWrite}
    try{[IO.FileStream]::new($ledgerPath,$ledgerOptions).Dispose()}catch{Block 'ledger'}
}

# The module is loaded from this checkout by name through PSModulePath (literal directory discovery).
$moduleRoot=[IO.Path]::GetFullPath([IO.Path]::Combine($PSScriptRoot,'..','..','module'))
$env:PSModulePath=$moduleRoot+[IO.Path]::PathSeparator+$env:PSModulePath
Import-Module Webmania
if((Get-Module Webmania).ModuleBase -ne [IO.Path]::Combine($moduleRoot,'Webmania')){Emit 'configuration' $null $false -Kind 'module_origin';exit 1}

$clients=@()
try{
    $four=@{ConsumerKey=(Secret $names[0]);ConsumerSecret=(Secret $names[1]);AccessToken=(Secret $names[2]);AccessTokenSecret=(Secret $names[3])}
    $nfe=New-WebmaniaCompanyClient @four -Options (Options $api1);$clients+=$nfe
    $emitter=New-WebmaniaIssuerClient -Bearer (Secret $names[4]) -Options (Options $api2);$clients+=$emitter
    $nfeFiles=New-WebmaniaApi1FilesCompanyClient @four -Options (Options $filesBase);$clients+=$nfeFiles
    $emitterFiles=New-WebmaniaApi2FilesCompanyBearerClient -Bearer (Secret $names[4]) -Options (Options $api2);$clients+=$emitterFiles

    $null=Call 'readonly.sefaz' 'nfeGetSefazStatus' {Get-WebmaniaNfeSefazStatus -Client $nfe -Parameters ([Webmania.NfeGetSefazStatusParameters]::new())}
    $null=Call 'readonly.certificate' 'nfeGetCertificateValidity' {Get-WebmaniaNfeCertificateValidity -Client $nfe -Parameters ([Webmania.NfeGetCertificateValidityParameters]::new())}
    $null=Call 'readonly.tax_classes' 'nfeListTaxClasses' {Get-WebmaniaNfeTaxClasses -Client $nfe -Parameters ([Webmania.NfeListTaxClassesParameters]::new())}
    $null=Call 'readonly.nfse_provider' 'emitterGetNfseProviderStatus' {Get-WebmaniaEmitterNfseProviderStatus -Client $emitter -Parameters ([Webmania.EmitterGetNfseProviderStatusParameters]::new())}

    if($null -ne $nfeDocument){
        $id="$($nfeDocument['ID'])"
        $issuedJson=$null
        try{
            $issued=Call 'nfe.issue' 'nfeIssueDocument' {Submit-WebmaniaNfeDocument -Client $nfe -Parameters (Params ([Webmania.NfeIssueDocumentParameters]) ('{"body":'+$nfeDocument.ToJsonString()+'}'))} $id -Mutation
            if($null -ne $issued){$issuedJson=Fields $issued.Json}
        }catch [UnknownOutcome]{Ledger 'nfe' $(if($id){$id}else{'unidentified'}) 'unknown' 'nfeIssueDocument';throw}
        $uuid=Text $issuedJson 'uuid'
        if($uuid){
            $issuedStatus=Text $issuedJson 'status';Ledger 'nfe' $uuid $(if($issuedStatus){$issuedStatus}else{'processando'}) 'nfeIssueDocument'
            $consult={Get-WebmaniaNfeDocument -Client $nfe -Parameters (Params ([Webmania.NfeGetDocumentParameters]) (Json @{uuid=$uuid}))}
            $current=Poll 'nfe.consult' 'nfeGetDocument' $consult {param($s) $s -in @('aprovado','reprovado','denegado','cancelado')} $uuid
            $currentStatus=Text $current 'status'
            if($currentStatus -ne 'aprovado'){Ledger 'nfe' $uuid $(if($currentStatus){$currentStatus}else{'unknown'}) 'nfeGetDocument'}
            else{
                $cancelled=$false
                try{
                    $null=Call 'nfe.query' 'nfeQueryDocument' {Find-WebmaniaNfeDocument -Client $nfe -Parameters (Params ([Webmania.NfeQueryDocumentParameters]) (Json @{body=@{uuid=$uuid}}))} $uuid
                    $null=Call 'nfe.danfe' 'nfeDownloadDanfe' {Receive-WebmaniaNfeDanfe -Client $nfeFiles -Parameters (Params ([Webmania.NfeDownloadDanfeParameters]) (Json @{identifier=$uuid}))} $uuid
                    $null=Call 'nfe.danfe_simple' 'nfeDownloadSimpleDanfe' {Receive-WebmaniaNfeSimpleDanfe -Client $nfeFiles -Parameters (Params ([Webmania.NfeDownloadSimpleDanfeParameters]) (Json @{identifier=$uuid}))} $uuid
                    $null=Call 'nfe.xml' 'nfeDownloadXml' {Receive-WebmaniaNfeXml -Client $nfeFiles -Parameters (Params ([Webmania.NfeDownloadXmlParameters]) (Json @{identifier=$uuid}))} $uuid
                }finally{
                    # An approved document is always cancelled, even after a failed step above.
                    # A cancellation whose outcome is unknown is recorded before the run stops.
                    try{$cancelled=$null -ne (Call 'nfe.cancel' 'nfeCancelDocument' {Stop-WebmaniaNfeDocument -Client $nfe -Parameters (Params ([Webmania.NfeCancelDocumentParameters]) (Json @{body=[ordered]@{uuid=$uuid;motivo='Cancelamento de teste em homologacao.'}}))} $uuid -Mutation)}
                    catch [UnknownOutcome]{Ledger 'nfe' $uuid 'unknown' 'nfeCancelDocument';throw}
                }
                if(-not $cancelled){Ledger 'nfe' $uuid 'aprovado' 'nfeCancelDocument'}
                else{
                    $final=Poll 'nfe.consult_cancelled' 'nfeGetDocument' $consult {param($s) $s -eq 'cancelado'} $uuid
                    $finalStatus=Text $final 'status';if(-not $finalStatus){$finalStatus='unknown'}
                    Ledger 'nfe' $uuid $finalStatus 'nfeCancelDocument'
                    # Only a consult that shows the cancellation counts as success.
                    if($finalStatus -eq 'cancelado'){$null=Call 'nfe.cancellation_xml' 'nfeDownloadCancellationXml' {Receive-WebmaniaNfeCancellationXml -Client $nfeFiles -Parameters (Params ([Webmania.NfeDownloadCancellationXmlParameters]) (Json @{identifier=$uuid}))} $uuid}
                    else{Emit 'nfe.consult_cancelled' 'nfeGetDocument' $false -Kind 'not_cancelled' -Reference (Ref $uuid)}
                }
            }
        }
    }

    if($null -ne $nfseDocument){
        $id="$($nfseDocument['ID'])"
        $json=$null
        try{
            $issued=Call 'nfse.issue' 'emitterIssueNfse' {Submit-WebmaniaEmitterNfse -Client $emitter -Parameters (Params ([Webmania.EmitterIssueNfseParameters]) ('{"body":'+$nfseDocument.ToJsonString()+'}'))} $id -Mutation
            if($null -ne $issued){$json=Fields $issued.Json}
        }catch [UnknownOutcome]{Ledger 'nfse' $(if($id){$id}else{'unidentified'}) 'unknown' 'emitterIssueNfse';throw}
        $uuid=Text $json 'uuid'
        $info=[Text.Json.JsonElement]::new()
        if(-not $uuid -and $null -ne $json -and $json.ValueKind -eq [Text.Json.JsonValueKind]::Object -and $json.TryGetProperty('info_nfse',[ref]$info) -and $info.ValueKind -eq [Text.Json.JsonValueKind]::Array -and $info.GetArrayLength() -gt 0){$uuid=Text $info[0] 'uuid'}
        if($uuid){
            $issuedStatus=Text $json 'status';Ledger 'nfse' $uuid $(if($issuedStatus){$issuedStatus}else{'processando'}) 'emitterIssueNfse'
            $consult={Get-WebmaniaEmitterNfse -Client $emitter -Parameters (Params ([Webmania.EmitterGetNfseParameters]) (Json @{identifier=$uuid}))}
            $current=Poll 'nfse.consult' 'emitterGetNfse' $consult {param($s) $s -notin @('','processando','pendente')} $uuid
            $currentStatus=Text $current 'status'
            if($currentStatus -ne 'aprovado'){Ledger 'nfse' $uuid $(if($currentStatus){$currentStatus}else{'unknown'}) 'emitterGetNfse'}
            else{
                $cancelled=$false
                try{
                    $null=Call 'nfse.xml' 'fileGetNfseXml' {Get-WebmaniaFileNfseXml -Client $emitterFiles -Parameters (Params ([Webmania.FileGetNfseXmlParameters]) (Json @{identifier=$uuid}))} $uuid
                    if(Text $current 'pdf_nfse'){$null=Call 'nfse.pdf' 'fileGetNfsePdf' {Get-WebmaniaFileNfsePdf -Client $emitterFiles -Parameters (Params ([Webmania.FileGetNfsePdfParameters]) (Json @{identifier=$uuid}))} $uuid}
                    else{Emit 'nfse.pdf' 'fileGetNfsePdf' $true -Kind 'not_offered' -Reference (Ref $uuid)}
                    if(Text $current 'pdf_rps'){$null=Call 'nfse.rps_pdf' 'fileGetNfseRpsPdf' {Get-WebmaniaFileNfseRpsPdf -Client $emitterFiles -Parameters (Params ([Webmania.FileGetNfseRpsPdfParameters]) (Json @{identifier=$uuid}))} $uuid}
                    else{Emit 'nfse.rps_pdf' 'fileGetNfseRpsPdf' $true -Kind 'not_offered' -Reference (Ref $uuid)}
                }finally{
                    try{$cancelled=$null -ne (Call 'nfse.cancel' 'emitterCancelNfse' {Stop-WebmaniaEmitterNfse -Client $emitter -Parameters (Params ([Webmania.EmitterCancelNfseParameters]) (Json @{body=[ordered]@{uuid=$uuid;motivo='1';justificativa='Cancelamento de teste em homologacao.'}}))} $uuid -Mutation)}
                    catch [UnknownOutcome]{Ledger 'nfse' $uuid 'unknown' 'emitterCancelNfse';throw}
                }
                if(-not $cancelled){Ledger 'nfse' $uuid 'aprovado' 'emitterCancelNfse'}
                else{
                    $final=Poll 'nfse.consult_cancelled' 'emitterGetNfse' $consult {param($s) $s -eq 'cancelado'} $uuid
                    $finalStatus=Text $final 'status';if(-not $finalStatus){$finalStatus='unknown'}
                    Ledger 'nfse' $uuid $finalStatus 'emitterCancelNfse'
                    if($finalStatus -ne 'cancelado'){Emit 'nfse.consult_cancelled' 'emitterGetNfse' $false -Kind 'not_cancelled' -Reference (Ref $uuid)}
                }
            }
        }
    }
}catch [UnknownOutcome]{exit 1}
catch{Emit 'configuration' $null $false -Kind 'configuration';exit 1}
finally{foreach($client in $clients){$client.Dispose()}}
exit $(if($script:failed -gt 0){1}else{0})
