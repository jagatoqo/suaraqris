#release.ps1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0, HelpMessage = "Versi rilis, mis. v1.0.1")]
    [ValidatePattern("^v\d+\.\d+\.\d+$")]
    [string]$Version,

    [Parameter(HelpMessage = "Rollback ke tag tertentu, mis. v1.0.0 (tanpa buat tag baru)")]
    [ValidatePattern("^v\d+\.\d+\.\d+$")]
    [string]$RollbackTo,

    [Parameter(HelpMessage = "Repo GitHub, format owner/repo")]
    [string]$Repo = "jagatoqo/suara-qris",

    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

$pointerMain = Join-Path $PSScriptRoot "latest.json"
$pointerBeta = Join-Path $PSScriptRoot "latest-beta.json"

function Write-Step([string]$msg) {
    Write-Host ""
    Write-Host "==> $msg" -ForegroundColor Cyan
}

function Invoke-Cmd([string]$label, [scriptblock]$block) {
    if ($DryRun) {
        Write-Host "  [dry-run] $label" -ForegroundColor Yellow
        return
    }
    Write-Host "  jalankan: $label"
    & $block
    if ($LASTEXITCODE -ne 0) { throw "Gagal: $label (exit $LASTEXITCODE)" }
}

function Write-Pointer([string]$path, [string]$target) {
    $content = "{`n  `"preset_url`": `"https://cdn.jsdelivr.net/gh/$Repo@$target`"`n}"
    if ($DryRun) {
        Write-Host "  [dry-run] tulis $([IO.Path]::GetFileName($path)) -> $target"
        return
    }
    [System.IO.File]::WriteAllText($path, $content, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "  $([IO.Path]::GetFileName($path)) -> $target"
}

function Invoke-PurgeAndVerify([string]$tag) {
    $purgeUrls = @(
        "https://purge.jsdelivr.net/gh/$Repo@main/latest.json",
        "https://purge.jsdelivr.net/gh/$Repo@main/latest-beta.json",
        "https://purge.jsdelivr.net/gh/$Repo@$tag/presets.json",
        "https://purge.jsdelivr.net/gh/$Repo@$tag/presets-beta.json"
    )

    Write-Step "Purge cache jsDelivr"
    foreach ($u in $purgeUrls) {
        Invoke-Cmd "purge $u" { & curl.exe -s $u }
    }

    Write-Step "Verifikasi pointer di CDN"
    if ($DryRun) { return }
    $body = (& curl.exe -s "https://cdn.jsdelivr.net/gh/$Repo@main/latest.json") -join ""
    Write-Host $body
    if ($body -match $tag) {
        Write-Host "  OK: CDN menunjuk ke $tag" -ForegroundColor Green
    } else {
        Write-Warning "CDN belum menunjukkan $tag - cache mungkin belum ter-purge. Ulangi purge atau cek header age:"
        Invoke-Cmd "cek age" { & curl.exe -sI "https://cdn.jsdelivr.net/gh/$Repo@main/latest.json" }
    }
}

# ---------- preflight ----------
Write-Step "Preflight"
foreach ($f in @("latest.json", "latest-beta.json", "presets.json")) {
    if (-not (Test-Path (Join-Path $PSScriptRoot $f))) {
        throw "File '$f' tidak ditemukan di $PSScriptRoot. Jalankan script ini dari root repo GitHub (tempat latest.json berada)."
    }
}

if (-not $DryRun) {
    $dirty = (& git status --porcelain 2>$null) | Where-Object { $_ -and $_ -notmatch 'latest(-beta)?\.json' }
    if ($dirty) {
        Write-Warning "Ada perubahan belum di-commit (selain pointer):"
        $dirty | ForEach-Object { Write-Host "  $_" }
        if (-not $RollbackTo) {
            $ans = Read-Host "Tag harus dibuat di commit berisi presets terbaru. Lanjutkan? [y/N]"
            if ($ans -ne "y") { Write-Host "Dibatalkan."; exit 1 }
        }
    }
}

# ---------- rollback ----------
if ($RollbackTo) {
    Write-Step "ROLLBACK pointer ke $RollbackTo"
    Write-Pointer $pointerMain "$RollbackTo/presets.json"
    Write-Pointer $pointerBeta "$RollbackTo/presets-beta.json"
    Invoke-Cmd "git add latest.json latest-beta.json" { git add latest.json latest-beta.json }
    Invoke-Cmd "git commit -m 'Rollback preset ke $RollbackTo'" { git commit -m "Rollback preset ke $RollbackTo" }
    Invoke-Cmd "git push origin main" { git push origin main }
    Invoke-PurgeAndVerify $RollbackTo
    Write-Host ""
    Write-Host "Rollback selesai. Buka app untuk memicu sync." -ForegroundColor Green
    exit 0
}

# ---------- release ----------
Write-Step "Buat tag $Version"
Invoke-Cmd "git tag $Version" { git tag $Version }

Write-Step "Update pointer ke $Version"
Write-Pointer $pointerMain "$Version/presets.json"
Write-Pointer $pointerBeta "$Version/presets-beta.json"

Write-Step "Commit pointer"
Invoke-Cmd "git add latest.json latest-beta.json" { git add latest.json latest-beta.json }
Invoke-Cmd "git commit -m 'Release $Version'" { git commit -m "Release $Version" }

Write-Step "Push main + tag"
Invoke-Cmd "git push origin main --follow-tags" { git push origin main --follow-tags }

Invoke-PurgeAndVerify $Version

Write-Host ""
Write-Host "Rilis $Version selesai. Buka app untuk memicu sync:"
Write-Host "  adb shell am force-stop com.suaraqris.app"
Write-Host "  adb shell am start -n com.suaraqris.app/.MainActivity"
Write-Host "  adb logcat -d | findstr PresetApplier" -ForegroundColor Green
