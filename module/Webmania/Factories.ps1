# Generated from explicit public credential factory names; credentials use SecureString.

function New-WebmaniaCompanyClient {
    <# .SYNOPSIS
    Creates an isolated Company credential client. Call Dispose() when finished.
    #>
    [CmdletBinding()][OutputType([Webmania.WebmaniaClient])]
    param([Parameter(Mandatory)][ValidateNotNull()][Webmania.PowerShell.SafeType([Security.SecureString])][Security.SecureString]$ConsumerKey,
        [Parameter(Mandatory)][ValidateNotNull()][Webmania.PowerShell.SafeType([Security.SecureString])][Security.SecureString]$ConsumerSecret,
        [Parameter(Mandatory)][ValidateNotNull()][Webmania.PowerShell.SafeType([Security.SecureString])][Security.SecureString]$AccessToken,
        [Parameter(Mandatory)][ValidateNotNull()][Webmania.PowerShell.SafeType([Security.SecureString])][Security.SecureString]$AccessTokenSecret,
        [Webmania.PowerShell.SafeType([Webmania.WebmaniaClientOptions])][Webmania.WebmaniaClientOptions]$Options=[Webmania.WebmaniaClientOptions]::new())
    try { [Webmania.WebmaniaClient]::new([Webmania.WebmaniaCredentials]::Company((Read-WebmaniaSecret $ConsumerKey),(Read-WebmaniaSecret $ConsumerSecret),(Read-WebmaniaSecret $AccessToken),(Read-WebmaniaSecret $AccessTokenSecret)),$Options) }
    catch { Stop-WebmaniaError $PSCmdlet $_ }
}
function New-WebmaniaIssuerClient {
    <# .SYNOPSIS
    Creates an isolated Issuer credential client. Call Dispose() when finished.
    #>
    [CmdletBinding()][OutputType([Webmania.WebmaniaClient])]
    param([Parameter(Mandatory)][ValidateNotNull()][Webmania.PowerShell.SafeType([Security.SecureString])][Security.SecureString]$Bearer,
        [Webmania.PowerShell.SafeType([Webmania.WebmaniaClientOptions])][Webmania.WebmaniaClientOptions]$Options=[Webmania.WebmaniaClientOptions]::new())
    try { [Webmania.WebmaniaClient]::new([Webmania.WebmaniaCredentials]::Issuer((Read-WebmaniaSecret $Bearer)),$Options) }
    catch { Stop-WebmaniaError $PSCmdlet $_ }
}
function New-WebmaniaMonitorClient {
    <# .SYNOPSIS
    Creates an isolated Monitor credential client. Call Dispose() when finished.
    #>
    [CmdletBinding()][OutputType([Webmania.WebmaniaClient])]
    param([Parameter(Mandatory)][ValidateNotNull()][Webmania.PowerShell.SafeType([Security.SecureString])][Security.SecureString]$Bearer,
        [Webmania.PowerShell.SafeType([Webmania.WebmaniaClientOptions])][Webmania.WebmaniaClientOptions]$Options=[Webmania.WebmaniaClientOptions]::new())
    try { [Webmania.WebmaniaClient]::new([Webmania.WebmaniaCredentials]::Monitor((Read-WebmaniaSecret $Bearer)),$Options) }
    catch { Stop-WebmaniaError $PSCmdlet $_ }
}
function New-WebmaniaResellerClient {
    <# .SYNOPSIS
    Creates an isolated Reseller credential client. Call Dispose() when finished.
    #>
    [CmdletBinding()][OutputType([Webmania.WebmaniaClient])]
    param([Parameter(Mandatory)][ValidateNotNull()][Webmania.PowerShell.SafeType([Security.SecureString])][Security.SecureString]$ConsumerKey,
        [Parameter(Mandatory)][ValidateNotNull()][Webmania.PowerShell.SafeType([Security.SecureString])][Security.SecureString]$ConsumerSecret,
        [Parameter(Mandatory)][ValidateNotNull()][Webmania.PowerShell.SafeType([Security.SecureString])][Security.SecureString]$AccessToken,
        [Parameter(Mandatory)][ValidateNotNull()][Webmania.PowerShell.SafeType([Security.SecureString])][Security.SecureString]$AccessTokenSecret,
        [Webmania.PowerShell.SafeType([Webmania.WebmaniaClientOptions])][Webmania.WebmaniaClientOptions]$Options=[Webmania.WebmaniaClientOptions]::new())
    try { [Webmania.WebmaniaClient]::new([Webmania.WebmaniaCredentials]::Reseller((Read-WebmaniaSecret $ConsumerKey),(Read-WebmaniaSecret $ConsumerSecret),(Read-WebmaniaSecret $AccessToken),(Read-WebmaniaSecret $AccessTokenSecret)),$Options) }
    catch { Stop-WebmaniaError $PSCmdlet $_ }
}
function New-WebmaniaApi1FilesCompanyClient {
    <# .SYNOPSIS
    Creates an isolated Api1FilesCompany credential client. Call Dispose() when finished.
    #>
    [CmdletBinding()][OutputType([Webmania.WebmaniaClient])]
    param([Parameter(Mandatory)][ValidateNotNull()][Webmania.PowerShell.SafeType([Security.SecureString])][Security.SecureString]$ConsumerKey,
        [Parameter(Mandatory)][ValidateNotNull()][Webmania.PowerShell.SafeType([Security.SecureString])][Security.SecureString]$ConsumerSecret,
        [Parameter(Mandatory)][ValidateNotNull()][Webmania.PowerShell.SafeType([Security.SecureString])][Security.SecureString]$AccessToken,
        [Parameter(Mandatory)][ValidateNotNull()][Webmania.PowerShell.SafeType([Security.SecureString])][Security.SecureString]$AccessTokenSecret,
        [Webmania.PowerShell.SafeType([Webmania.WebmaniaClientOptions])][Webmania.WebmaniaClientOptions]$Options=[Webmania.WebmaniaClientOptions]::new())
    try { [Webmania.WebmaniaClient]::new([Webmania.WebmaniaCredentials]::Api1FilesCompany((Read-WebmaniaSecret $ConsumerKey),(Read-WebmaniaSecret $ConsumerSecret),(Read-WebmaniaSecret $AccessToken),(Read-WebmaniaSecret $AccessTokenSecret)),$Options) }
    catch { Stop-WebmaniaError $PSCmdlet $_ }
}
function New-WebmaniaApi1ReportCapabilityClient {
    <# .SYNOPSIS
    Creates an isolated Api1ReportCapability credential client. Call Dispose() when finished.
    #>
    [CmdletBinding()][OutputType([Webmania.WebmaniaClient])]
    param([Webmania.PowerShell.SafeType([Webmania.WebmaniaClientOptions])][Webmania.WebmaniaClientOptions]$Options=[Webmania.WebmaniaClientOptions]::new())
    try { [Webmania.WebmaniaClient]::new([Webmania.WebmaniaCredentials]::Api1ReportCapability(),$Options) }
    catch { Stop-WebmaniaError $PSCmdlet $_ }
}
function New-WebmaniaReportCapabilityClient {
    <# .SYNOPSIS
    Creates an isolated ReportCapability credential client. Call Dispose() when finished.
    #>
    [CmdletBinding()][OutputType([Webmania.WebmaniaClient])]
    param([Webmania.PowerShell.SafeType([Webmania.WebmaniaClientOptions])][Webmania.WebmaniaClientOptions]$Options=[Webmania.WebmaniaClientOptions]::new())
    try { [Webmania.WebmaniaClient]::new([Webmania.WebmaniaCredentials]::ReportCapability(),$Options) }
    catch { Stop-WebmaniaError $PSCmdlet $_ }
}
function New-WebmaniaApi1FilesDocumentTokenClient {
    <# .SYNOPSIS
    Creates an isolated Api1FilesDocumentToken credential client. Call Dispose() when finished.
    #>
    [CmdletBinding()][OutputType([Webmania.WebmaniaClient])]
    param([Parameter(Mandatory)][ValidateNotNull()][Webmania.PowerShell.SafeType([Security.SecureString])][Security.SecureString]$Token,
        [Webmania.PowerShell.SafeType([Webmania.WebmaniaClientOptions])][Webmania.WebmaniaClientOptions]$Options=[Webmania.WebmaniaClientOptions]::new())
    try { [Webmania.WebmaniaClient]::new([Webmania.WebmaniaCredentials]::Api1FilesDocumentToken((Read-WebmaniaSecret $Token)),$Options) }
    catch { Stop-WebmaniaError $PSCmdlet $_ }
}
function New-WebmaniaApi2FilesCompanyBearerClient {
    <# .SYNOPSIS
    Creates an isolated Api2FilesCompanyBearer credential client. Call Dispose() when finished.
    #>
    [CmdletBinding()][OutputType([Webmania.WebmaniaClient])]
    param([Parameter(Mandatory)][ValidateNotNull()][Webmania.PowerShell.SafeType([Security.SecureString])][Security.SecureString]$Bearer,
        [Webmania.PowerShell.SafeType([Webmania.WebmaniaClientOptions])][Webmania.WebmaniaClientOptions]$Options=[Webmania.WebmaniaClientOptions]::new())
    try { [Webmania.WebmaniaClient]::new([Webmania.WebmaniaCredentials]::Api2FilesCompanyBearer((Read-WebmaniaSecret $Bearer)),$Options) }
    catch { Stop-WebmaniaError $PSCmdlet $_ }
}
function New-WebmaniaApi2FilesDocumentTokenClient {
    <# .SYNOPSIS
    Creates an isolated Api2FilesDocumentToken credential client. Call Dispose() when finished.
    #>
    [CmdletBinding()][OutputType([Webmania.WebmaniaClient])]
    param([Parameter(Mandatory)][ValidateNotNull()][Webmania.PowerShell.SafeType([Security.SecureString])][Security.SecureString]$Token,
        [Webmania.PowerShell.SafeType([Webmania.WebmaniaClientOptions])][Webmania.WebmaniaClientOptions]$Options=[Webmania.WebmaniaClientOptions]::new())
    try { [Webmania.WebmaniaClient]::new([Webmania.WebmaniaCredentials]::Api2FilesDocumentToken((Read-WebmaniaSecret $Token)),$Options) }
    catch { Stop-WebmaniaError $PSCmdlet $_ }
}
function New-WebmaniaApi2FilesAnonymousClient {
    <# .SYNOPSIS
    Creates an isolated Api2FilesAnonymous credential client. Call Dispose() when finished.
    #>
    [CmdletBinding()][OutputType([Webmania.WebmaniaClient])]
    param([Webmania.PowerShell.SafeType([Webmania.WebmaniaClientOptions])][Webmania.WebmaniaClientOptions]$Options=[Webmania.WebmaniaClientOptions]::new())
    try { [Webmania.WebmaniaClient]::new([Webmania.WebmaniaCredentials]::Api2FilesAnonymous(),$Options) }
    catch { Stop-WebmaniaError $PSCmdlet $_ }
}
