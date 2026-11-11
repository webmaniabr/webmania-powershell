param([Parameter(Mandatory)][string]$Manifest,[Parameter(Mandatory)][int]$Port)
$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
Import-Module $Manifest
$secret=ConvertTo-SecureString 'alpha6-depth-synthetic' -AsPlainText -Force
$o=[Webmania.WebmaniaClientOptions]::new();$o.LoopbackTestEndpoint=[uri]"http://127.0.0.1:$Port/";$o.Timeout=[timespan]::FromSeconds(2)
$c=New-WebmaniaCompanyClient -ConsumerKey $secret -ConsumerSecret $secret -AccessToken $secret -AccessTokenSecret $secret -Options $o
$deep='"depth-child-private"';foreach($n in 1..4096){$deep='{"n":'+$deep+'}'}
$opts=[Text.Json.JsonDocumentOptions]::new();$opts.MaxDepth=5000;$doc=[Text.Json.JsonDocument]::Parse($deep,$opts)
try{
 $body=[Webmania.Api1FiscalFiscalCompanyUpdateRequest]::new();$body.Extras.Add('nested',$doc.RootElement)
 $p=[Webmania.FiscalUpdateCompanyParameters]::new();$p.Body=[Webmania.Optional[Webmania.Api1FiscalFiscalCompanyUpdateRequest]]::Of($body)
 $caught=$null;try{Set-WebmaniaFiscalCompany -Client $c -Parameters $p|Out-Null}catch{$caught=$_}
 if($null -eq $caught -or $caught.ToString().Contains('depth-child-private')){throw 'Depth child did not reject privately'}
 @{status='pass';depth=4096;processSurvived=$true;errorId=$caught.FullyQualifiedErrorId;assemblyOrigin=[Webmania.WebmaniaClient].Assembly.Location}|ConvertTo-Json -Compress
}finally{$doc.Dispose();$c.Dispose()}
