# Builds release zips into .\dist
#   ClaudeExport-<ver>.zip         -> unzip into Interface\AddOns (contains the ClaudeExport folder)
#   wow-companion-<ver>.zip        -> the Claude Code plugin folder
#   ClaudeExport-full-<ver>.zip    -> everything (addon + plugin + marketplace + docs)
# Uses System.IO.Compression directly: Compress-Archive in Windows PowerShell 5.1 writes
# backslashes into entry names, which breaks extraction on macOS/Linux.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem

$root = $PSScriptRoot
$toc = Get-Content -LiteralPath (Join-Path $root 'addon\ClaudeExport\ClaudeExport.toc')
$ver = (($toc | Where-Object { $_ -match '^## Version:' }) -replace '^## Version:\s*', '').Trim()
$dist = Join-Path $root 'dist'
New-Item -ItemType Directory -Force -Path $dist | Out-Null
Get-ChildItem -LiteralPath $dist -Filter *.zip | Remove-Item -Force

# $entries: list of @(sourcePath, pathInsideZip); folders are added recursively
function New-Zip($zipPath, $entries) {
  $zip = [System.IO.Compression.ZipFile]::Open($zipPath, 'Create')
  try {
    foreach ($e in $entries) {
      $src = Join-Path $root $e[0]
      $files = if (Test-Path -LiteralPath $src -PathType Container) {
        Get-ChildItem -LiteralPath $src -Recurse -File -Force
      } else { Get-Item -LiteralPath $src }
      foreach ($f in $files) {
        $rel = $f.FullName.Substring((Resolve-Path -LiteralPath $src).Path.Length).TrimStart('\')
        $name = if ($rel) { "$($e[1])/$rel" } else { $e[1] }
        $name = $name -replace '\\', '/'
        [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $f.FullName, $name)
      }
    }
  } finally { $zip.Dispose() }
}

New-Zip (Join-Path $dist "ClaudeExport-$ver.zip") @(, @('addon\ClaudeExport', 'ClaudeExport'))
New-Zip (Join-Path $dist "wow-companion-$ver.zip") @(, @('plugin\wow-companion', 'wow-companion'))
New-Zip (Join-Path $dist "ClaudeExport-full-$ver.zip") @(
  @('addon', 'addon'), @('plugin', 'plugin'), @('.claude-plugin', '.claude-plugin'),
  @('README.md', 'README.md'), @('LICENSE', 'LICENSE'), @('CHANGELOG.md', 'CHANGELOG.md')
)

Get-ChildItem -LiteralPath $dist | Select-Object Name, Length
