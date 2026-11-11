param([Parameter(Mandatory)][string]$OutputDirectory)
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Split-Path $PSScriptRoot))
$module=[IO.Path]::Combine($root,'module','Webmania')
function Test-Within([string]$Path,[string]$Parent){
    $child=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($Path))
    $base=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($Parent))
    $child -eq $base -or $child.StartsWith($base+[IO.Path]::DirectorySeparatorChar,[StringComparison]::Ordinal)
}
# Paths are literal (no wildcard expansion). Only the archive and package-manifest.json are written to the
# output directory; nothing in it is deleted except a previous archive file of the same name.
$output=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDirectory)
if(Test-Within $output $module){throw 'OutputDirectory must be outside module/Webmania.'}
[void][IO.Directory]::CreateDirectory($output)
# The module is staged in a private temporary directory created here, and only that directory is removed.
$stage=[IO.Path]::Combine([IO.Path]::GetTempPath(),'webmania-package-'+[guid]::NewGuid().ToString('N'))
if((Test-Path -LiteralPath $stage) -or (Test-Within $stage $root) -or (Test-Within $root $stage)){throw 'Unsafe staging directory.'}
$stage=[IO.Directory]::CreateDirectory($stage).FullName
try{
    Copy-Item -LiteralPath $module -Destination $stage -Recurse -Force
    $manifest=Import-PowerShellDataFile -LiteralPath ([IO.Path]::Combine($module,'Webmania.psd1'))
    $archive=[IO.Path]::Combine($output,'Webmania.'+$manifest.ModuleVersion+'-'+$manifest.PrivateData.PSData.Prerelease+'.zip')
    if([IO.Directory]::Exists($archive)){throw 'The archive path is a directory.'}
    if([IO.File]::Exists($archive)){[IO.File]::Delete($archive)}
    $staged=[IO.Path]::Combine($stage,'Webmania')
    # Stable entry order and timestamp; reproducibility is scoped to the pinned runtime.
    $stream=[IO.File]::Open($archive,[IO.FileMode]::CreateNew)
    try{
        $zip=[IO.Compression.ZipArchive]::new($stream,[IO.Compression.ZipArchiveMode]::Create,$true)
        try{
            foreach($file in (Get-ChildItem -LiteralPath $staged -Recurse -File|Sort-Object FullName)){
                $name=$file.FullName.Substring($stage.Length+1).Replace('\','/')
                $entry=$zip.CreateEntry($name,[IO.Compression.CompressionLevel]::Optimal)
                $entry.LastWriteTime=[DateTimeOffset]::new(1980,1,1,0,0,0,[TimeSpan]::Zero)
                $target=$entry.Open();$source=$file.OpenRead()
                try{$source.CopyTo($target)}finally{$source.Dispose();$target.Dispose()}
            }
        }finally{$zip.Dispose()}
    }finally{$stream.Dispose()}
    $files=Get-ChildItem -LiteralPath $staged -Recurse -File|Sort-Object FullName|ForEach-Object {
        @{path=$_.FullName.Substring($stage.Length+1);sha256=(Get-FileHash -LiteralPath $_.FullName).Hash.ToLowerInvariant();bytes=$_.Length}
    }
    @{archive=(Split-Path $archive -Leaf);sha256=(Get-FileHash -LiteralPath $archive).Hash.ToLowerInvariant();files=@($files)}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath ([IO.Path]::Combine($output,'package-manifest.json'))
    Write-Output "Packaged $archive"
}finally{
    Remove-Item -LiteralPath $stage -Recurse -Force
}
