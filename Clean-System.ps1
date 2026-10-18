<#
.SYNOPSIS
    Windows System Cleanup (No Windows Update handling)
#>

$ErrorActionPreference = "SilentlyContinue"
Clear-Host

function Write-Header { param([string]$Text)
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor DarkCyan
    Write-Host "  $Text" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor DarkCyan
}
function Write-Item { param([string]$Text, [string]$Status = "INFO")
    $color = switch ($Status) { "OK" {"Green"} "SKIP" {"DarkGray"} "WARN" {"Yellow"} "ERROR" {"Red"} default {"White"} }
    $prefix = switch ($Status) { "OK" {"[ OK ]"} "SKIP" {"[SKIP]"} "WARN" {"[WARN]"} "ERROR" {"[FAIL]"} default {"[INFO]"} }
    Write-Host "  $prefix $Text" -ForegroundColor $color
}
function Get-FolderSizeMB { param([string]$Path)
    if (-not (Test-Path $Path)) { return 0 }
    try { return [math]::Round(((Get-ChildItem $Path -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum) / 1MB, 2) }
    catch { return 0 }
}
function Remove-Contents { param([string]$Path, [string]$Label)
    if (-not (Test-Path $Path)) { Write-Item "$Label - not found" "SKIP"; return 0 }
    $before = Get-FolderSizeMB -Path $Path
    try {
        Get-ChildItem -Path $Path -Recurse -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        $after = Get-FolderSizeMB -Path $Path
        $freed = [math]::Round($before - $after, 2)
        Write-Item "$Label - freed $freed MB" "OK"
        return $freed
    } catch { Write-Item "$Label - partial" "WARN"; return 0 }
}

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "  [!] Must run as Administrator." -ForegroundColor Red
    pause; exit 1
}

$startTime = Get-Date
$startFree = (Get-PSDrive C).Free

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "        WINDOWS SYSTEM CLEANUP (Safe Mode)" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host "  Free space before: $([math]::Round($startFree/1GB,2)) GB" -ForegroundColor Gray

$totalFreed = 0

Write-Header "1/10 - User Temp"
$totalFreed += Remove-Contents -Path $env:TEMP -Label "User temp"

Write-Header "2/10 - Windows Temp"
$totalFreed += Remove-Contents -Path "C:\Windows\Temp" -Label "Windows temp"

Write-Header "3/10 - Recent Items"
foreach ($p in @("$env:APPDATA\Microsoft\Windows\Recent","$env:APPDATA\Microsoft\Windows\Recent\AutomaticDestinations","$env:APPDATA\Microsoft\Windows\Recent\CustomDestinations")) {
    $totalFreed += Remove-Contents -Path $p -Label (Split-Path $p -Leaf)
}

Write-Header "4/10 - Prefetch"
$totalFreed += Remove-Contents -Path "C:\Windows\Prefetch" -Label "Prefetch"

Write-Header "5/10 - Thumbnail & Icon Cache"
$thumbPath = "$env:LOCALAPPDATA\Microsoft\Windows\Explorer"
if (Test-Path $thumbPath) {
    $count = (Get-ChildItem -Path $thumbPath -Filter "thumbcache_*.db" -Force -ErrorAction SilentlyContinue).Count
    Get-ChildItem -Path $thumbPath -Filter "thumbcache_*.db" -Force -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    Get-ChildItem -Path $thumbPath -Filter "iconcache_*.db" -Force -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    Write-Item "Thumbnail/icon caches - $count files removed" "OK"
}

Write-Header "6/10 - DNS Cache"
ipconfig /flushdns | Out-Null
Write-Item "DNS resolver cache flushed" "OK"

Write-Header "7/10 - Recycle Bin"
$rbBefore = Get-FolderSizeMB -Path "C:\`$Recycle.Bin"
Clear-RecycleBin -Force -ErrorAction SilentlyContinue
Write-Item "Recycle bin emptied (~$rbBefore MB)" "OK"
$totalFreed += $rbBefore

Write-Header "8/10 - Browser Caches"
$browserCaches = @(
    @{ Name="Edge";   Path="$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Cache" },
    @{ Name="Edge";   Path="$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Code Cache" },
    @{ Name="Chrome"; Path="$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Cache" },
    @{ Name="Chrome"; Path="$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Code Cache" }
)
foreach ($b in $browserCaches) {
    if (Test-Path $b.Path) { $totalFreed += Remove-Contents -Path $b.Path -Label "$($b.Name) cache" }
}

Write-Header "9/10 - Crash Dumps & Error Reports"
foreach ($p in @("C:\Windows\Minidump","$env:LOCALAPPDATA\CrashDumps","$env:LOCALAPPDATA\Microsoft\Windows\WER\ReportQueue","$env:LOCALAPPDATA\Microsoft\Windows\WER\ReportArchive")) {
    if (Test-Path $p) { $totalFreed += Remove-Contents -Path $p -Label (Split-Path $p -Leaf) }
}

Write-Header "10/10 - Old Log Files (>30 days)"
$logCount = 0
foreach ($p in @("C:\Windows\Logs","C:\Windows\System32\LogFiles")) {
    if (Test-Path $p) {
        Get-ChildItem -Path $p -Recurse -Filter "*.log" -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) } |
            ForEach-Object { Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue; $logCount++ }
    }
}
Write-Item "Removed $logCount old log files" "OK"

$endFree = (Get-PSDrive C).Free
$actuallyFreed = [math]::Round(($endFree - $startFree) / 1MB, 2)
$duration = [math]::Round(((Get-Date) - $startTime).TotalSeconds, 1)

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "                   CLEANUP COMPLETE" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host "  Duration:        $duration seconds" -ForegroundColor White
Write-Host "  Estimated freed: $totalFreed MB" -ForegroundColor White
Write-Host "  Actual freed:    $actuallyFreed MB" -ForegroundColor Cyan
Write-Host "  Free space now:  $([math]::Round($endFree/1GB,2)) GB" -ForegroundColor Cyan
Write-Host ""
Read-Host "  Press Enter to exit"