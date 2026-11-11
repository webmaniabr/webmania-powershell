function Read-WebmaniaSecret([Webmania.PowerShell.SafeType([Security.SecureString])][Security.SecureString]$Value){
    if($null -eq $Value -or $Value.Length -eq 0){throw [ArgumentException]::new('A nonempty credential is required.')}
    $ptr=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($Value)
    try{return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)}finally{[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)}
}
function Stop-WebmaniaError([Webmania.PowerShell.SafeType([System.Management.Automation.PSCmdlet])][System.Management.Automation.PSCmdlet]$Caller,[Webmania.PowerShell.SafeType([System.Management.Automation.ErrorRecord])][System.Management.Automation.ErrorRecord]$Failure){
    $stopped=$Failure.Exception
    while($null -ne $stopped){if($stopped -is [Management.Automation.PipelineStoppedException]){throw $stopped};$stopped=$stopped.InnerException}
    $e=$Failure.Exception
    while($null -ne $e -and $e -isnot [Webmania.WebmaniaException] -and $e -isnot [Webmania.PowerShell.WebmaniaPowerShellCancellationException]){
        if($e -is [Webmania.WebmaniaCancellationException]){$e=$e.Diagnostic;break}
        $e=$e.InnerException
    }
    if($null -ne $e){
        $record=[Management.Automation.ErrorRecord]::new($e,"Webmania.$($e.Kind)",[Management.Automation.ErrorCategory]::InvalidOperation,$null)
        $record.ErrorDetails=[Management.Automation.ErrorDetails]::new($e.ToString()+"`n"+$e.RecoveryAdvice)
    }else{
        $safe=[InvalidOperationException]::new('Webmania input or local operation failed. Check typed parameters, credential values and client options.')
        $record=[Management.Automation.ErrorRecord]::new($safe,'Webmania.LocalValidation',[Management.Automation.ErrorCategory]::InvalidArgument,$null)
    }
    $Caller.ThrowTerminatingError($record)
}
function Get-WebmaniaOperation {
    <# .SYNOPSIS
    Lists pinned operation capability and contract status, including the blocked operation.
    #>
    [CmdletBinding()][OutputType([Webmania.OperationInfo])]
    param()
    [Webmania.WebmaniaClient]::Operations
}
function New-WebmaniaJsonNumber {
    <# .SYNOPSIS
    Creates an exact JSON number from decimal text without floating point conversion.
    #>
    [CmdletBinding()][OutputType([Webmania.JsonNumber])]
    param([Parameter(Mandatory)][Webmania.PowerShell.SafeType([string])][string]$Text)
    try{[Webmania.JsonNumber]::new($Text)}catch{Stop-WebmaniaError $PSCmdlet $_}
}
function New-WebmaniaOptional {
    <# .SYNOPSIS
    Creates an explicit omitted, null or present Optional[T] value. -Type is the inner type.
    #>
    [CmdletBinding(DefaultParameterSetName='Value')]
    param([Parameter(Mandatory)][Webmania.PowerShell.SafeType([type])][type]$Type,
        [Parameter(Mandatory,ParameterSetName='Value')][AllowNull()][Webmania.PowerShell.SafeType([object])][object]$Value,
        [Parameter(Mandatory,ParameterSetName='Null')][Alias('Null')][Webmania.PowerShell.SafeType([Management.Automation.SwitchParameter])][switch]$ExplicitNull,
        [Parameter(Mandatory,ParameterSetName='Omitted')][Webmania.PowerShell.SafeType([Management.Automation.SwitchParameter])][switch]$Omitted)
    try{
        $optional=[Webmania.Optional``1].MakeGenericType($Type)
        if($Omitted){$result=[Activator]::CreateInstance($optional)}
        elseif($ExplicitNull){$result=$optional.GetProperty('Null').GetValue($null)}
        else{
            if($null -ne $Value -and -not $Type.IsInstanceOfType($Value)){throw 'Optional value must already have its declared type.'}
            $result=$optional.GetMethod('Of').Invoke($null,[object[]]@(,$Value))
        }
        $PSCmdlet.WriteObject($result,$false)
    }catch{Stop-WebmaniaError $PSCmdlet $_}
}
