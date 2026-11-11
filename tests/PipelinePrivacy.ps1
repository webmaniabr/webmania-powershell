param([Parameter(Mandatory)][string]$Archive,[Parameter(Mandatory)][string]$OutputDirectory)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
trap {Write-Output $_.ToString();Write-Output $_.ScriptStackTrace;throw $_}
$install=Join-Path '/tmp' ('pipeline-privacy-'+[guid]::NewGuid().ToString('N'))
Expand-Archive $Archive $install
Import-Module (Join-Path $install 'Webmania/Webmania.psd1')
Add-Type -Path (Join-Path $PSScriptRoot 'LifecycleFixture.cs')
Add-Type -Path (Join-Path $PSScriptRoot 'SocketFixture.cs')
Add-Type @'
public sealed class PrivatePipelineInput {
 public string Secret {get;set;}=""; public int ToStringCalls {get;private set;}
 public override string ToString(){ToStringCalls++;throw new System.InvalidOperationException("pipeline-private: "+Secret);}
}
'@
$marker='ALPHA5'+'-PRIVATE-PIPELINE-917C24'
$custom=[PrivatePipelineInput]::new();$custom.Secret=$marker
$results=[Collections.Generic.List[object]]::new()
$declared=[Collections.Generic.List[object]]::new()
function Check([bool]$Condition,[string]$Name){if(-not $Condition){throw "Pipeline privacy assertion failed: $Name"}}
foreach($command in (Get-Command -Module Webmania)){
    foreach($parameter in $command.Parameters.Values){
        $sets=@($parameter.ParameterSets.GetEnumerator()|Where-Object {$_.Value.ValueFromPipeline -or $_.Value.ValueFromPipelineByPropertyName})
        if($sets.Count){$declared.Add(@{command=$command.Name;parameter=$parameter.Name;type=$parameter.ParameterType.ToString();sets=@($sets|ForEach-Object {$_.Key})})}
    }
}
Check ($declared.Count -eq 1 -and $declared[0].command -eq 'Save-WebmaniaFile' -and $declared[0].parameter -eq 'PipelineInput') 'all declared SDK pipeline surfaces audited'
$save=Get-Command Save-WebmaniaFile
Check ($save.Parameters.InputObject.ParameterType -eq [Webmania.FileResult]) 'named InputObject remains strongly typed'
Check ($save.Parameters.PipelineInput.ParameterType -eq [object]) 'declared pipeline catchall consumes before engine rejection'
function Snapshot($Caught){
    $snapshot=[ordered]@{default=($Caught|Out-String -Width 4096);full=($Caught|Format-List * -Force|Out-String -Width 4096);exception=$Caught.Exception.ToString()}
    $objects=@(@{prefix='ErrorRecord';value=$Caught},@{prefix='InvocationInfo';value=$Caught.InvocationInfo})
    $exception=$Caught.Exception;$index=0
    while($null -ne $exception -and $index -lt 8){$objects+=@{prefix="Exception.$index";value=$exception};$exception=$exception.InnerException;$index++}
    foreach($entry in $objects){foreach($property in $entry.value.GetType().GetProperties()){
        try{$snapshot[$entry.prefix+'.'+$property.Name]=($property.GetValue($entry.value)|Format-List * -Force|Out-String -Width 4096)}catch{$snapshot[$entry.prefix+'.'+$property.Name]='[getter failed]'}
    }}
    return $snapshot
}
$server=[IndependentServer]::new($true)
$options=[Webmania.WebmaniaClientOptions]::new();$options.LoopbackTestEndpoint=$server.Url;$options.LoopbackTestRootCertificate=$server.Root
$client=New-WebmaniaApi1ReportCapabilityClient -Options $options
$filesDirectory=Join-Path $OutputDirectory 'pipeline-save-controls';New-Item -ItemType Directory $filesDirectory|Out-Null
try{
    $server.Enqueue([IndependentReply]@{Body=([Text.Encoding]::ASCII.GetString([PsSocketFixture]::Pdf()));Media='application/pdf'})
    $p=[Webmania.FiscalDownloadReportParameters]::new();$p.Uuid='82b58d19-f30c-4d22-9951-22c76f282451'
    $file=Receive-WebmaniaFiscalReport -Client $client -Parameters $p
    Check ($file.IsFile -and $server.Count -eq 1) 'genuine validated FileResult prepared'
    $sentinel=[Webmania.PowerShell.ProtectedInvalidInput].GetField('Instance',[Reflection.BindingFlags]'NonPublic,Static').GetValue($null)
    $secure=ConvertTo-SecureString $marker -AsPlainText -Force
    $values=@(
        @{name='private-string';value=$marker},
        @{name='PSCustomObject-private-property';value=([pscustomobject]@{Secret=$marker})},
        @{name='hostile-ToString';value=$custom},
        @{name='PSObject-wrapped-hostile';value=([psobject]$custom)},
        @{name='actual-invalid-sentinel';value=$sentinel},
        @{name='SecureString-private-value';value=$secure},
        @{name='hashtable-private-value';value=@{Secret=$marker}},
        @{name='opaque-array-private-values';value=([object[]]@($custom,$marker))},
        @{name='opaque-string-array-private-values';value=([string[]]@($marker,$marker))}
    )
    function Reject([string]$Name,[scriptblock]$Action,[object]$Original){
        $beforeRequests=$server.Count;$beforeFiles=@(Get-ChildItem -LiteralPath $filesDirectory -File)
        $caught=$null;try{& $Action|Out-Null}catch{$caught=$_}
        Check ($null -ne $caught) "$Name rejected"
        Check ($null -eq $caught.TargetObject) "$Name error target is null"
        Check ($caught.FullyQualifiedErrorId -notlike 'InputObjectNotBound,*') "$Name rejection owned by SDK"
        if($caught.InvocationInfo.BoundParameters.ContainsKey('PipelineInput')){
            $bound=$caught.InvocationInfo.BoundParameters['PipelineInput']
            Check ($null -eq $bound -or $bound -is [Webmania.PowerShell.ProtectedInvalidInput] -or $bound -is [Webmania.FileResult]) "$Name owned pipeline binding safe"
            if($null -ne $Original){Check (-not [object]::ReferenceEquals($bound,$Original)) "$Name original not retained in binding"}
        }
        $snapshot=Snapshot $caught
        foreach($text in $snapshot.Values){Check (-not $text.Contains($marker)) "$Name marker absent from all error surfaces"}
        Check ($custom.ToStringCalls -eq 0) "$Name no hostile ToString during binding or formatting"
        Check ($server.Count -eq $beforeRequests) "$Name zero SDK requests"
        Check (@(Get-ChildItem -LiteralPath $filesDirectory -File).Count -eq $beforeFiles.Count) "$Name zero file writes"
        $results.Add(@{case=$Name;errorId=$caught.FullyQualifiedErrorId;targetNull=$true;snapshot=$snapshot;hostileToStringCalls=$custom.ToStringCalls;rejectionRequests=0;rejectionFileWrites=0;pass=$true})
    }
    foreach($item in $values){
        $path=Join-Path $filesDirectory 'never-write.pdf'
        Reject "declared-pipeline-$($item.name)" {Write-Output -NoEnumerate $item.value|Save-WebmaniaFile -LiteralPath $path -Debug} $item.value
        Reject "named-catchall-$($item.name)" {Save-WebmaniaFile -PipelineInput $item.value -LiteralPath $path -Debug} $item.value
        Reject "named-file-plus-pipeline-$($item.name)" {Write-Output -NoEnumerate $item.value|Save-WebmaniaFile -InputObject $file -LiteralPath $path -Debug} $item.value
        Reject "C07-prebound-receiver-plus-pipeline-$($item.name)" {Write-Output -NoEnumerate $item.value|Save-WebmaniaFile -PipelineInput $file -LiteralPath $path -Debug} $item.value
        Reject "C08-both-prebound-plus-pipeline-$($item.name)" {Write-Output -NoEnumerate $item.value|Save-WebmaniaFile -InputObject $file -PipelineInput $file -LiteralPath $path -Debug} $item.value
        $prebound=@{PipelineInput=$file;LiteralPath=$path}
        Reject "splatted-receiver-plus-pipeline-$($item.name)" {Write-Output -NoEnumerate $item.value|Save-WebmaniaFile @prebound -Debug} $item.value
        $bothPrebound=@{InputObject=$file;PipelineInput=$file;LiteralPath=$path}
        Reject "splatted-both-plus-pipeline-$($item.name)" {Write-Output -NoEnumerate $item.value|Save-WebmaniaFile @bothPrebound -Debug} $item.value
    }
    Reject 'enumerated-private-array' {@($marker,$custom)|Save-WebmaniaFile -LiteralPath (Join-Path $filesDirectory 'never-array.pdf')} $marker
    Reject 'named-typed-file-rejects-hostile' {Save-WebmaniaFile -InputObject $custom -LiteralPath (Join-Path $filesDirectory 'never-named.pdf')} $custom
    Reject 'valid-pipeline-plus-unsafe-path' {$file|Save-WebmaniaFile -LiteralPath $custom} $custom
    Reject 'private-pipeline-plus-unsafe-path' {$custom|Save-WebmaniaFile -LiteralPath $custom} $custom
    Reject 'valid-named-plus-valid-pipeline-ambiguous' {$file|Save-WebmaniaFile -InputObject $file -LiteralPath (Join-Path $filesDirectory 'never-combined.pdf')} $file
    Reject 'explicit-null-catchall' {Save-WebmaniaFile -PipelineInput $null -LiteralPath (Join-Path $filesDirectory 'never-null.pdf')} $null
    Reject 'explicit-valid-receiver-without-pipe' {Save-WebmaniaFile -PipelineInput $file -LiteralPath (Join-Path $filesDirectory 'never-explicit-valid.pdf')} $file
    Reject 'both-explicit-valid-without-pipe' {Save-WebmaniaFile -InputObject $file -PipelineInput $file -LiteralPath (Join-Path $filesDirectory 'never-both-valid.pdf')} $file
    Reject 'prebound-null-plus-hostile-pipeline' {$custom|Save-WebmaniaFile -PipelineInput $null -LiteralPath (Join-Path $filesDirectory 'never-null-pipe.pdf')} $custom
    Reject 'prebound-hostile-plus-private-pipeline' {$marker|Save-WebmaniaFile -PipelineInput $custom -LiteralPath (Join-Path $filesDirectory 'never-hostile-pipe.pdf')} $marker
    $nullPrebound=@{PipelineInput=$null;LiteralPath=(Join-Path $filesDirectory 'never-splat-null-pipe.pdf')}
    Reject 'splatted-null-plus-hostile-pipeline' {$custom|Save-WebmaniaFile @nullPrebound} $custom
    $hostilePrebound=@{PipelineInput=$custom;LiteralPath=(Join-Path $filesDirectory 'never-splat-hostile-pipe.pdf')}
    Reject 'splatted-hostile-plus-private-pipeline' {$marker|Save-WebmaniaFile @hostilePrebound} $marker
    $validPrebound=@{PipelineInput=$file;LiteralPath=(Join-Path $filesDirectory 'never-splat-valid.pdf')}
    Reject 'splatted-valid-without-pipe' {Save-WebmaniaFile @validPrebound} $file
    Reject 'splatted-null-without-pipe' {Save-WebmaniaFile @nullPrebound} $null
    Reject 'splatted-hostile-without-pipe' {Save-WebmaniaFile @hostilePrebound} $custom
    Check (@(Get-ChildItem -LiteralPath $filesDirectory -File).Count -eq 0) 'all invalid inputs leave directory empty'
    $pipelinePath=Join-Path $filesDirectory 'valid-pipeline.pdf'
    $namedPath=Join-Path $filesDirectory 'valid-named.pdf'
    $pipelineSaved=$file|Save-WebmaniaFile -LiteralPath $pipelinePath
    $namedSaved=Save-WebmaniaFile -InputObject $file -LiteralPath $namedPath
    foreach($saved in @($pipelineSaved,$namedSaved)){
        Check ($saved -is [IO.FileInfo] -and $saved.Length -eq $file.Bytes.Length) 'valid file input produces FileInfo with exact size'
        Check ([Convert]::ToBase64String([IO.File]::ReadAllBytes($saved.FullName)) -ceq [Convert]::ToBase64String($file.Bytes.ToArray())) 'valid file bytes preserved'
    }
    Check ($custom.ToStringCalls -eq 0) 'complete error formatting never executes hostile ToString'
    @{status='pass';declaredPipelineParameters=@($declared);namedInputObjectType=$save.Parameters.InputObject.ParameterType.FullName;rejections=@($results);rejectionCount=$results.Count;rejectionRequests=0;rejectionFileWrites=0;hostileToStringCalls=$custom.ToStringCalls;preparationRequests=$server.Count;validFileWrites=2;explicitReceiverBinding='rejected in begin before per-record binding, with or without a pipe';namedAndPipelineCombination='rejected before write'}|ConvertTo-Json -Depth 20|Set-Content (Join-Path $OutputDirectory 'pipeline-privacy-results.json')
    Write-Output "PASS: $($declared.Count) declared pipeline surface; $($results.Count) private rejections / null targets / 0 ToString / 0 rejection requests or writes; 2 genuine file controls"
}finally{$client.Dispose();$server.Dispose()}
