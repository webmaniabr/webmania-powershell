param([Parameter(Mandatory)][string]$OutputDirectory)
$ErrorActionPreference='Stop';$results=[Collections.Generic.List[object]]::new()
$root=Split-Path $PSScriptRoot
foreach($file in (Get-ChildItem $root -Recurse -File|Where-Object {$_.Extension -in @('.ps1','.psm1','.psd1')}|Sort-Object FullName)){
 $tokens=$null;$errors=$null;$null=[Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
 $results.Add(@{path=$file.FullName.Substring($root.Length+1);syntaxErrors=$errors.Count})
 if($errors.Count){$errors|Out-String|Write-Output;throw 'PowerShell syntax validation failed'}
}
@{status='pass';files=@($results);kind='PowerShell7.6 parser syntax; PSScriptAnalyzer not installed in offline pinned image, not claimed'}|ConvertTo-Json -Depth 8|Set-Content (Join-Path $OutputDirectory lint.json)
Write-Output "PASS: PowerShell parser syntax in$($results.Count) source files"
