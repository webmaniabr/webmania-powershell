param([Parameter(Mandatory)][string]$Archive,[Parameter(Mandatory)][string]$OutputDirectory)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
trap {Write-Output $_.ToString();Write-Output $_.ScriptStackTrace;throw $_}
$install=Join-Path '/tmp' ('scalar-privacy-'+[guid]::NewGuid().ToString('N'))
Expand-Archive $Archive $install
Import-Module (Join-Path $install 'Webmania/Webmania.psd1')
Add-Type -Path (Join-Path $PSScriptRoot 'LifecycleFixture.cs')
Add-Type -Path (Join-Path $PSScriptRoot 'SocketFixture.cs')
Add-Type @'
using System;
public sealed class ScalarRejectedInput {
 public string Secret=""; public int ToStringCalls;
 public override string ToString(){ToStringCalls++;throw new InvalidOperationException("private-conversion: "+Secret);}
}
public sealed class ScalarRejectedConvertible : IConvertible {
 public string Secret=""; public int ConversionCalls;
 private Exception Reject(){ConversionCalls++;return new InvalidOperationException("private-convertible: "+Secret);}
 public override string ToString()=>throw Reject();
 public TypeCode GetTypeCode()=>throw Reject();
 public bool ToBoolean(IFormatProvider p)=>throw Reject();
 public byte ToByte(IFormatProvider p)=>throw Reject();
 public char ToChar(IFormatProvider p)=>throw Reject();
 public DateTime ToDateTime(IFormatProvider p)=>throw Reject();
 public decimal ToDecimal(IFormatProvider p)=>throw Reject();
 public double ToDouble(IFormatProvider p)=>throw Reject();
 public short ToInt16(IFormatProvider p)=>throw Reject();
 public int ToInt32(IFormatProvider p)=>throw Reject();
 public long ToInt64(IFormatProvider p)=>throw Reject();
 public sbyte ToSByte(IFormatProvider p)=>throw Reject();
 public float ToSingle(IFormatProvider p)=>throw Reject();
 public string ToString(IFormatProvider p)=>throw Reject();
 public object ToType(Type t,IFormatProvider p)=>throw Reject();
 public ushort ToUInt16(IFormatProvider p)=>throw Reject();
 public uint ToUInt32(IFormatProvider p)=>throw Reject();
 public ulong ToUInt64(IFormatProvider p)=>throw Reject();
}
'@
$marker='ALPHA3'+'-PRIVATE-REJECTED-SCALAR-917B4C'
$custom=[ScalarRejectedInput]::new();$custom.Secret=$marker
$convertible=[ScalarRejectedConvertible]::new();$convertible.Secret=$marker
$audit=[Collections.Generic.List[object]]::new();$results=[Collections.Generic.List[object]]::new()
function Check([bool]$Condition,[string]$Name){if(-not $Condition){throw "Scalar privacy assertion failed: $Name"}}
function Snapshot($Caught,[bool]$Deep){
    $snapshot=[ordered]@{default=($Caught|Out-String -Width 4096);full=($Caught|Format-List * -Force|Out-String -Width 4096);exception=$Caught.Exception.ToString();invocation=($Caught.InvocationInfo|Format-List * -Force|Out-String -Width 4096)}
    if($Deep){
        $objects=@(@{prefix='ErrorRecord';value=$Caught},@{prefix='InvocationInfo';value=$Caught.InvocationInfo})
        $exception=$Caught.Exception;$index=0
        while($null -ne $exception -and $index -lt 8){$objects+=@{prefix="Exception.$index";value=$exception};$exception=$exception.InnerException;$index++}
        foreach($entry in $objects){foreach($property in $entry.value.GetType().GetProperties()){
            try{$snapshot[$entry.prefix+'.'+$property.Name]=($property.GetValue($entry.value)|Format-List * -Force|Out-String -Width 4096)}catch{$snapshot[$entry.prefix+'.'+$property.Name]='[getter failed]'}
        }}
    }
    return $snapshot
}
$server=[IndependentServer]::new($true)
$options=[Webmania.WebmaniaClientOptions]::new();$options.LoopbackTestEndpoint=$server.Url;$options.LoopbackTestRootCertificate=$server.Root
$secret=ConvertTo-SecureString 'synthetic-scalar-privacy' -AsPlainText -Force
$client=New-WebmaniaApi1ReportCapabilityClient -Options $options
try{
    # Genuine file result is required to prove path rejection before file writes.
    $server.Enqueue([IndependentReply]@{Body=([Text.Encoding]::ASCII.GetString([PsSocketFixture]::Pdf()));Media='application/pdf'})
    $p=[Webmania.FiscalDownloadReportParameters]::new();$p.Uuid='82b58d19-f30c-4d22-9951-22c76f282451'
    $file=Receive-WebmaniaFiscalReport -Client $client -Parameters $p
    Check ($file.IsFile -and $server.Count -eq 1) 'genuine SDK validated file prepared'
    function Reject([string]$Name,[string]$Command,[hashtable]$Arguments,[bool]$Deep=$false){
        $beforeRequests=$server.Count;$beforeFiles=@(Get-ChildItem -LiteralPath $OutputDirectory -File|Select-Object -ExpandProperty Name)
        $caught=$null;try{& $Command @Arguments -Debug|Out-Null}catch{$caught=$_}
        Check ($null -ne $caught) "$Name rejected"
        $snapshot=Snapshot $caught $Deep
        foreach($text in $snapshot.Values){Check (-not $text.Contains($marker)) "$Name private marker absent"}
        Check ($custom.ToStringCalls -eq 0) "$Name unknown ToString never called"
        Check ($convertible.ConversionCalls -eq 0) "$Name unknown IConvertible never called"
        Check ($server.Count -eq $beforeRequests) "$Name zero I/O"
        $afterFiles=@(Get-ChildItem -LiteralPath $OutputDirectory -File|Select-Object -ExpandProperty Name)
        Check (-not (Compare-Object $beforeFiles $afterFiles)) "$Name creates no file"
        $results.Add(@{case=$Name;command=$Command;errorId=$caught.FullyQualifiedErrorId;snapshot=$snapshot;unknownToStringCalls=$custom.ToStringCalls;requestsDelta=0;filesCreated=0;pass=$true})
    }
    $common=@('Verbose','Debug','ErrorAction','WarningAction','InformationAction','ProgressAction','ErrorVariable','WarningVariable','InformationVariable','OutVariable','OutBuffer','PipelineVariable')
    # Audit every owned public binder. Object Value is an identity data binder;
    # it remains typed object and performs no implicit string conversion.
    foreach($command in (Get-Command -Module Webmania|Sort-Object Name)){
        foreach($parameter in $command.Parameters.Values){
            if($parameter.Name -in $common){continue}
            $guarded=@($parameter.Attributes|Where-Object {$_ -is [Webmania.PowerShell.SafeTypeAttribute]}).Count -gt 0
            Check $guarded "owned binder guard $($command.Name).$($parameter.Name)"
            $audit.Add(@{command=$command.Name;parameter=$parameter.Name;type=$parameter.ParameterType.ToString();arrayType=$parameter.ParameterType.IsArray;guarded=$guarded})
            $arguments=@{};$arguments[$parameter.Name]=$custom
            if($parameter.Name -eq 'Value'){$arguments.Type=[string]}
            if($parameter.Name -eq 'LiteralPath'){$arguments.InputObject=$file}
            if($parameter.Name -eq 'PipelineInput'){$arguments.LiteralPath=(Join-Path $OutputDirectory 'scalar-pipeline-never-write')}
            Reject "owned-custom-$($command.Name).$($parameter.Name)" $command.Name $arguments
        }
    }
    $sentinel=[Webmania.PowerShell.ProtectedInvalidInput].GetField('Instance',[Reflection.BindingFlags]'NonPublic,Static').GetValue($null)
    $unsafeInputs=@(
        @{name='custom-throwing-object';value=$custom},
        @{name='custom-IConvertible';value=$convertible},
        @{name='PSObject-wrapped-custom';value=([psobject]$custom)},
        @{name='object-array-custom';value=([object[]]@($custom,$marker))},
        @{name='string-array-private';value=([string[]]@($marker,$marker))},
        @{name='native-number-array';value=([int[]]@(1,2))},
        @{name='hashtable-private';value=@{Secret=$marker}},
        @{name='PSCustomObject-private';value=([pscustomobject]@{Secret=$marker})},
        @{name='protected-invalid-sentinel';value=$sentinel}
    )
    foreach($inputCase in $unsafeInputs){
        Reject "number-$($inputCase.name)" 'New-WebmaniaJsonNumber' @{Text=$inputCase.value} $true
        Reject "path-$($inputCase.name)" 'Save-WebmaniaFile' @{InputObject=$file;LiteralPath=$inputCase.value} $true
    }
    $lexical=@('1.2300000000000000000000000000000001e+200','9223372036854775808123456789','-0','1e0')
    foreach($text in $lexical){$number=New-WebmaniaJsonNumber -Text $text;Check ($number.Text -ceq $text) 'literal lexical number unchanged'}
    $native=@([byte]1,[sbyte]2,[short]3,[ushort]4,[int]5,[uint]6,[long]7,[ulong]8,[Int128]9,[UInt128]10,[IntPtr]11,[UIntPtr]12,[Numerics.BigInteger]13,[decimal]14.2500,[single]15.5,[double]16.25,[Half]17.5,[char]'1')
    foreach($value in $native){
        $number=New-WebmaniaJsonNumber -Text $value
        Check ($number -is [Webmania.JsonNumber]) "native scalar accepted $($value.GetType().Name)"
    }
    $decimal=New-WebmaniaJsonNumber -Text ([decimal]::Parse('1.2300',[Globalization.CultureInfo]::InvariantCulture))
    Check ($decimal.Text -ceq '1.2300') 'native decimal scale retained'
    Reject 'native-bool-is-not-JSON-number' 'New-WebmaniaJsonNumber' @{Text=$false}
    Push-Location $OutputDirectory
    try{
        $literal=Join-Path $OutputDirectory 'scalar-literal.pdf'
        $saved=Save-WebmaniaFile -InputObject $file -LiteralPath $literal
        Check ($saved.Length -eq $file.Bytes.Length) 'valid literal file path retains behavior'
        $saved=Save-WebmaniaFile -InputObject $file -LiteralPath ([int]44017)
        Check ($saved.Name -ceq '44017') 'native integer path uses invariant scalar conversion'
        $saved=Save-WebmaniaFile -InputObject $file -LiteralPath $false
        Check ($saved.Name -ceq 'False') 'native Boolean path uses intrinsic scalar conversion'
        Check (-not (Test-Path -LiteralPath '[protected-invalid-input]')) 'rejected sentinel never becomes filename'
    }finally{Pop-Location}
    $arrayValue=[string[]]@('one','two');$optional=New-WebmaniaOptional -Type ([string[]]) -Value $arrayValue
    Check ($optional.IsSet -and $optional.Value.Count -eq 2 -and $optional.Value[1] -ceq 'two') 'typed object-array data remains identity-bound'
    Check ($custom.ToStringCalls -eq 0) 'all unknown conversions stayed unexecuted'
    @{status='pass';ownedBinders=@($audit);rejections=@($results);rejectionCount=$results.Count;ownedBinderCount=$audit.Count;declaredArrayBinders=@($audit|Where-Object arrayType).Count;unknownToStringCalls=$custom.ToStringCalls;unknownIConvertibleCalls=$convertible.ConversionCalls;literalLexicalControls=$lexical.Count;nativeScalarControls=$native.Count;preparationRequests=$server.Count;rejectionRequests=0;rejectionFileWrites=0}|ConvertTo-Json -Depth 18|Set-Content (Join-Path $OutputDirectory 'scalar-privacy-results.json')
    Write-Output "PASS: $($audit.Count) owned binders audited; $($results.Count) private conversion rejections; 0 unknown ToString calls / rejection requests / file writes"
}finally{$client.Dispose();$server.Dispose()}
