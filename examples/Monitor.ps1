param([Parameter(Mandatory)][Security.SecureString]$Bearer)
$ErrorActionPreference='Stop'
$client=New-WebmaniaMonitorClient -Bearer $Bearer
try{
    $parameters=[Webmania.MonitorListCompaniesParameters]::new()
    $parameters.PerPage=New-WebmaniaOptional -Type ([Webmania.JsonNumber]) -Value (New-WebmaniaJsonNumber -Text '10')
    Get-WebmaniaMonitorCompanyItem -Client $client -Parameters $parameters -MaximumPages 3
}finally{$client.Dispose()}
