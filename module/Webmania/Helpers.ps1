function Wait-WebmaniaFiscalReport {
    <# .SYNOPSIS
    Waits for a fiscal report using the bounded SDK helper, with no authentication fallback or API error retry.
    #>
    [CmdletBinding()][OutputType([Webmania.ApiResponse[Webmania.FiscalCreateOrPollReportResult]])]
    param([Parameter(Mandatory)][Webmania.PowerShell.SafeType([Webmania.WebmaniaClient])][Webmania.WebmaniaClient]$Client,
        [Parameter(Mandatory)][Webmania.PowerShell.SafeType([Webmania.FiscalCreateOrPollReportParameters])][Webmania.FiscalCreateOrPollReportParameters]$Parameters,
        [Webmania.PowerShell.SafeType([Webmania.PollOptions])][Webmania.PollOptions]$Options=[Webmania.PollOptions]::new(),
        [Webmania.PowerShell.SafeType([Threading.CancellationToken])][Threading.CancellationToken]$CancellationToken=[Threading.CancellationToken]::None,
        [Webmania.PowerShell.SafeType([Management.Automation.SwitchParameter])][switch]$AsTask)
    try{
        Invoke-WebmaniaInternalCall -Client $Client -MethodName 'PollFiscalReportAsync' -Parameters $Parameters -PollOptions $Options -CancellationToken $CancellationToken -AsTask:$AsTask
    }catch{Stop-WebmaniaError $PSCmdlet $_}
}
function Get-WebmaniaMonitorCompanyItem {
    <# .SYNOPSIS
    Enumerates typed Monitor companies with a bounded page count through the existing SDK helper.
    #>
    [CmdletBinding()][OutputType([Webmania.Api2MonitorReadsMonitorCompany])]
    param([Parameter(Mandatory)][Webmania.PowerShell.SafeType([Webmania.WebmaniaClient])][Webmania.WebmaniaClient]$Client,
        [Parameter(Mandatory)][Webmania.PowerShell.SafeType([Webmania.MonitorListCompaniesParameters])][Webmania.MonitorListCompaniesParameters]$Parameters,
        [ValidateRange(1,10000)][Webmania.PowerShell.SafeType([int])][int]$MaximumPages=100,
        [Webmania.PowerShell.SafeType([Threading.CancellationToken])][Threading.CancellationToken]$CancellationToken=[Threading.CancellationToken]::None)
    try{Invoke-WebmaniaInternalCall -Client $Client -MethodName 'IterateMonitorCompaniesAsync' -Parameters $Parameters -MaximumPages $MaximumPages -CancellationToken $CancellationToken}
    catch{Stop-WebmaniaError $PSCmdlet $_}
}
function Get-WebmaniaMonitorCompanyMunicipalityItem {
    <# .SYNOPSIS
    Enumerates typed Monitor municipality registrations with a bounded page count.
    #>
    [CmdletBinding()][OutputType([Webmania.Api2MonitorReadsMonitorMunicipalityRegistration])]
    param([Parameter(Mandatory)][Webmania.PowerShell.SafeType([Webmania.WebmaniaClient])][Webmania.WebmaniaClient]$Client,
        [Parameter(Mandatory)][Webmania.PowerShell.SafeType([Webmania.MonitorListCompanyMunicipalitiesParameters])][Webmania.MonitorListCompanyMunicipalitiesParameters]$Parameters,
        [ValidateRange(1,10000)][Webmania.PowerShell.SafeType([int])][int]$MaximumPages=100,
        [Webmania.PowerShell.SafeType([Threading.CancellationToken])][Threading.CancellationToken]$CancellationToken=[Threading.CancellationToken]::None)
    try{Invoke-WebmaniaInternalCall -Client $Client -MethodName 'IterateMonitorCompanyMunicipalitiesAsync' -Parameters $Parameters -MaximumPages $MaximumPages -CancellationToken $CancellationToken}
    catch{Stop-WebmaniaError $PSCmdlet $_}
}
function Get-WebmaniaMonitorReportItem {
    <# .SYNOPSIS
    Enumerates typed Monitor reports with a bounded page count.
    #>
    [CmdletBinding()][OutputType([Webmania.Api2MonitorDocumentsMonitorReport])]
    param([Parameter(Mandatory)][Webmania.PowerShell.SafeType([Webmania.WebmaniaClient])][Webmania.WebmaniaClient]$Client,
        [Parameter(Mandatory)][Webmania.PowerShell.SafeType([Webmania.MonitorListReportsParameters])][Webmania.MonitorListReportsParameters]$Parameters,
        [ValidateRange(1,10000)][Webmania.PowerShell.SafeType([int])][int]$MaximumPages=100,
        [Webmania.PowerShell.SafeType([Threading.CancellationToken])][Threading.CancellationToken]$CancellationToken=[Threading.CancellationToken]::None)
    try{Invoke-WebmaniaInternalCall -Client $Client -MethodName 'IterateMonitorReportsAsync' -Parameters $Parameters -MaximumPages $MaximumPages -CancellationToken $CancellationToken}
    catch{Stop-WebmaniaError $PSCmdlet $_}
}
function Save-WebmaniaFile {
    <# .SYNOPSIS
    Writes an SDK validated file result. HTML, JSON, redirect and opaque representations are rejected; existing files require -Force.
    .DESCRIPTION
    Use strongly typed named InputObject or pipe a FileResult through guarded PipelineInput. PipelineInput is reserved for pipeline binding and cannot be explicitly supplied. Combining named and pipeline input is rejected. Invalid pipeline values are consumed and protected before producing an error; only validated FileResult values reach file writes.
    #>
    [CmdletBinding(DefaultParameterSetName='Pipeline')][OutputType([IO.FileInfo])]
    param([Parameter(Mandatory,ParameterSetName='Named')][Webmania.PowerShell.SafeType([Webmania.FileResult])][Webmania.FileResult]$InputObject,
        [Parameter(Mandatory,ValueFromPipeline,ParameterSetName='Pipeline')][Parameter(ValueFromPipeline,ParameterSetName='Named')][AllowNull()][Webmania.PowerShell.SafeType([Webmania.FileResult])][object]$PipelineInput,
        [Parameter(Mandatory)][Webmania.PowerShell.SafeType([string])][string]$LiteralPath,[Webmania.PowerShell.SafeType([Management.Automation.SwitchParameter])][switch]$Force)
    begin{
        # An explicitly prebound receiver cannot consume later pipeline values.
        # Reject this setup before per-record binding can retain an incoming
        # private value in an engine InputObjectNotBound error.
        if($PSBoundParameters.ContainsKey('PipelineInput')){
            $PipelineInput=$null
            $PSBoundParameters['PipelineInput']=$null
            $MyInvocation.BoundParameters['PipelineInput']=$null
            $safe=[InvalidOperationException]::new('PipelineInput is reserved for pipeline binding; use InputObject for named input.')
            $record=[Management.Automation.ErrorRecord]::new($safe,'Webmania.LocalValidation',[Management.Automation.ErrorCategory]::InvalidArgument,$null)
            $PSCmdlet.ThrowTerminatingError($record)
        }
    }
    process{
        try{
            $hasNamed=$PSBoundParameters.ContainsKey('InputObject')
            $hasPipeline=$PSBoundParameters.ContainsKey('PipelineInput')
            if($hasPipeline){
                # Consume every declared pipeline value before the engine can
                # retain it in InputObjectNotBound. Keep owned binding state safe
                # as well as ErrorRecord.TargetObject, including combined inputs.
                $PipelineInput=[Webmania.PowerShell.SafeTypeAttribute]::new([Webmania.FileResult]).Transform($ExecutionContext,$PipelineInput)
                $PSBoundParameters['PipelineInput']=$PipelineInput
            }
            if($hasNamed -and $hasPipeline){throw 'Choose named file input or pipeline file input.'}
            $file=if($hasNamed){$InputObject}else{$PipelineInput}
            if($file -isnot [Webmania.FileResult] -or -not $file.IsFile){throw 'The response is not a validated file representation.'}
            $path=$PSCmdlet.GetUnresolvedProviderPathFromPSPath($LiteralPath)
            $mode=if($Force){[IO.FileMode]::Create}else{[IO.FileMode]::CreateNew}
            $stream=[IO.File]::Open($path,$mode,[IO.FileAccess]::Write,[IO.FileShare]::None)
            try{$bytes=$file.Bytes.ToArray();$stream.Write($bytes,0,$bytes.Length)}finally{$stream.Dispose()}
            Get-Item -LiteralPath $path
        }catch{Stop-WebmaniaError $PSCmdlet $_}
    }
}

function Wait-WebmaniaMonitorImport {
    <# .SYNOPSIS
    Waits on an existing import UUID through the bounded SDK helper; terminal invalido is returned as typed data.
    #>
    [CmdletBinding()][OutputType([Webmania.ApiResponse[Webmania.Api2MonitorDocumentsMonitorImportStatus]])]
    param([Parameter(Mandatory)][Webmania.PowerShell.SafeType([Webmania.WebmaniaClient])][Webmania.WebmaniaClient]$Client,
        [Parameter(Mandatory)][Webmania.PowerShell.SafeType([Webmania.MonitorGetImportStatusParameters])][Webmania.MonitorGetImportStatusParameters]$Parameters,
        [Webmania.PowerShell.SafeType([Webmania.PollOptions])][Webmania.PollOptions]$Options=[Webmania.PollOptions]::new(),
        [Webmania.PowerShell.SafeType([Threading.CancellationToken])][Threading.CancellationToken]$CancellationToken=[Threading.CancellationToken]::None,
        [Webmania.PowerShell.SafeType([Management.Automation.SwitchParameter])][switch]$AsTask)
    try{Invoke-WebmaniaInternalCall -Client $Client -MethodName 'WaitMonitorImportAsync' -Parameters $Parameters -PollOptions $Options -CancellationToken $CancellationToken -AsTask:$AsTask}
    catch{Stop-WebmaniaError $PSCmdlet $_}
}

function Read-WebmaniaMonitorCompanyBatch {
    <# .SYNOPSIS
    Reads bounded typed items using an opaque in-memory SDK continuation bound to the original filters and page size.
    .DESCRIPTION
    Reuse the original Parameters snapshot and Continuation to resume without repeating buffered rows. The continuation is not a portable or serializable token.
    #>
    [CmdletBinding()][OutputType([Webmania.MonitorBatch[Webmania.Api2MonitorReadsMonitorCompany]])]
    param([Parameter(Mandatory)][Webmania.PowerShell.SafeType([Webmania.WebmaniaClient])][Webmania.WebmaniaClient]$Client,
        [Parameter(Mandatory)][Webmania.PowerShell.SafeType([Webmania.MonitorListCompaniesParameters])][Webmania.MonitorListCompaniesParameters]$Parameters,
        [Parameter(Mandatory)][ValidateRange(1,1000000)][Webmania.PowerShell.SafeType([int])][int]$MaximumItems,
        [AllowNull()][Webmania.PowerShell.SafeType([Webmania.MonitorContinuation[Webmania.Api2MonitorReadsMonitorCompany]])][Webmania.MonitorContinuation[Webmania.Api2MonitorReadsMonitorCompany]]$Continuation,
        [ValidateRange(1,10000)][Webmania.PowerShell.SafeType([int])][int]$MaximumPages=100,
        [Webmania.PowerShell.SafeType([Threading.CancellationToken])][Threading.CancellationToken]$CancellationToken=[Threading.CancellationToken]::None,
        [Webmania.PowerShell.SafeType([Management.Automation.SwitchParameter])][switch]$AsTask)
    try{Invoke-WebmaniaInternalCall -Client $Client -MethodName 'ReadMonitorCompaniesAsync' -Parameters $Parameters -MaximumItems $MaximumItems -Continuation $Continuation -MaximumPages $MaximumPages -CancellationToken $CancellationToken -AsTask:$AsTask}
    catch{Stop-WebmaniaError $PSCmdlet $_}
}

function Read-WebmaniaMonitorCompanyMunicipalityBatch {
    <# .SYNOPSIS
    Reads bounded typed items using an opaque in-memory SDK continuation bound to the original filters and page size.
    .DESCRIPTION
    Reuse the original Parameters snapshot and Continuation to resume without repeating buffered rows. The continuation is not a portable or serializable token.
    #>
    [CmdletBinding()][OutputType([Webmania.MonitorBatch[Webmania.Api2MonitorReadsMonitorMunicipalityRegistration]])]
    param([Parameter(Mandatory)][Webmania.PowerShell.SafeType([Webmania.WebmaniaClient])][Webmania.WebmaniaClient]$Client,
        [Parameter(Mandatory)][Webmania.PowerShell.SafeType([Webmania.MonitorListCompanyMunicipalitiesParameters])][Webmania.MonitorListCompanyMunicipalitiesParameters]$Parameters,
        [Parameter(Mandatory)][ValidateRange(1,1000000)][Webmania.PowerShell.SafeType([int])][int]$MaximumItems,
        [AllowNull()][Webmania.PowerShell.SafeType([Webmania.MonitorContinuation[Webmania.Api2MonitorReadsMonitorMunicipalityRegistration]])][Webmania.MonitorContinuation[Webmania.Api2MonitorReadsMonitorMunicipalityRegistration]]$Continuation,
        [ValidateRange(1,10000)][Webmania.PowerShell.SafeType([int])][int]$MaximumPages=100,
        [Webmania.PowerShell.SafeType([Threading.CancellationToken])][Threading.CancellationToken]$CancellationToken=[Threading.CancellationToken]::None,
        [Webmania.PowerShell.SafeType([Management.Automation.SwitchParameter])][switch]$AsTask)
    try{Invoke-WebmaniaInternalCall -Client $Client -MethodName 'ReadMonitorCompanyMunicipalitiesAsync' -Parameters $Parameters -MaximumItems $MaximumItems -Continuation $Continuation -MaximumPages $MaximumPages -CancellationToken $CancellationToken -AsTask:$AsTask}
    catch{Stop-WebmaniaError $PSCmdlet $_}
}

function Read-WebmaniaMonitorReportBatch {
    <# .SYNOPSIS
    Reads bounded typed items using an opaque in-memory SDK continuation bound to the original filters and page size.
    .DESCRIPTION
    Reuse the original Parameters snapshot and Continuation to resume without repeating buffered rows. The continuation is not a portable or serializable token.
    #>
    [CmdletBinding()][OutputType([Webmania.MonitorBatch[Webmania.Api2MonitorDocumentsMonitorReport]])]
    param([Parameter(Mandatory)][Webmania.PowerShell.SafeType([Webmania.WebmaniaClient])][Webmania.WebmaniaClient]$Client,
        [Parameter(Mandatory)][Webmania.PowerShell.SafeType([Webmania.MonitorListReportsParameters])][Webmania.MonitorListReportsParameters]$Parameters,
        [Parameter(Mandatory)][ValidateRange(1,1000000)][Webmania.PowerShell.SafeType([int])][int]$MaximumItems,
        [AllowNull()][Webmania.PowerShell.SafeType([Webmania.MonitorContinuation[Webmania.Api2MonitorDocumentsMonitorReport]])][Webmania.MonitorContinuation[Webmania.Api2MonitorDocumentsMonitorReport]]$Continuation,
        [ValidateRange(1,10000)][Webmania.PowerShell.SafeType([int])][int]$MaximumPages=100,
        [Webmania.PowerShell.SafeType([Threading.CancellationToken])][Threading.CancellationToken]$CancellationToken=[Threading.CancellationToken]::None,
        [Webmania.PowerShell.SafeType([Management.Automation.SwitchParameter])][switch]$AsTask)
    try{Invoke-WebmaniaInternalCall -Client $Client -MethodName 'ReadMonitorReportsAsync' -Parameters $Parameters -MaximumItems $MaximumItems -Continuation $Continuation -MaximumPages $MaximumPages -CancellationToken $CancellationToken -AsTask:$AsTask}
    catch{Stop-WebmaniaError $PSCmdlet $_}
}
