param(
    [Parameter(Mandatory)][Webmania.WebmaniaClient]$CompanyClient,
    [Parameter(Mandatory)][Webmania.WebmaniaClient]$IssuerClient,
    [Parameter(Mandatory)][string]$NfeId,
    [Parameter(Mandatory)][string]$NfseIdentifier,
    [Parameter(Mandatory)][string]$CteIdentifier,
    [Parameter(Mandatory)][string]$MdfeKey,
    [Parameter(Mandatory)][string]$NfcomUuid,
    [Parameter(Mandatory)][string]$DceIdentifier
)
$ErrorActionPreference='Stop'
# Import the module before invoking this script. Supply identifiers owned by you.
# The caller owns both clients and must dispose them after outstanding work.
$nfe=[Webmania.NfeGetDocumentParameters]::new();$nfe.ID=[Webmania.Optional[string]]::Of($NfeId)
Get-WebmaniaNfeDocument -Client $CompanyClient -Parameters $nfe
$nfse=[Webmania.EmitterGetNfseParameters]::new();$nfse.Identifier=[Webmania.Optional[string]]::Of($NfseIdentifier)
Get-WebmaniaEmitterNfse -Client $IssuerClient -Parameters $nfse
$cte=[Webmania.EmitterGetCteParameters]::new();$cte.Identifier=[Webmania.Optional[string]]::Of($CteIdentifier)
Get-WebmaniaEmitterCte -Client $IssuerClient -Parameters $cte
$mdfe=[Webmania.EmitterGetMdfeParameters]::new();$mdfe.Key=[Webmania.Optional[string]]::Of($MdfeKey)
Get-WebmaniaEmitterMdfe -Client $IssuerClient -Parameters $mdfe
$nfcom=[Webmania.EmitterGetNfcomParameters]::new();$nfcom.Identifier=[Webmania.Optional[string]]::Of($NfcomUuid)
Get-WebmaniaEmitterNfcom -Client $IssuerClient -Parameters $nfcom
$dce=[Webmania.EmitterGetDceParameters]::new();$dce.Identifier=[Webmania.Optional[string]]::Of($DceIdentifier)
Get-WebmaniaEmitterDce -Client $IssuerClient -Parameters $dce
