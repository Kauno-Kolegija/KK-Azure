param(
    [Parameter(Mandatory = $true)][string]$ResourceGroup,
    [Parameter(Mandatory = $true)][string]$WebAppName,
    [string]$FunctionAppName = "func-$WebAppName"
)

$ErrorActionPreference = 'Stop'
$null = Get-Command az -ErrorAction Stop
$sourceDir = Join-Path $PSScriptRoot '../Source'
$functionDir = Join-Path $sourceDir 'Functions'
$siteZip = Join-Path $PSScriptRoot ('site-' + [guid]::NewGuid().ToString('N') + '.zip')
$functionZip = Join-Path $PSScriptRoot ('func-' + [guid]::NewGuid().ToString('N') + '.zip')

foreach ($required in @('default.asp', 'health.asp', 'Functions/host.json', 'Functions/LogMover/function.json')) {
    if (-not (Test-Path -LiteralPath (Join-Path $sourceDir $required))) { throw "Trūksta failo: $required" }
}
try {
    $siteFiles = @(Get-ChildItem -LiteralPath $sourceDir -Filter '*.asp' -File | Select-Object -ExpandProperty FullName)
    Compress-Archive -LiteralPath $siteFiles -DestinationPath $siteZip
    az webapp deploy --resource-group $ResourceGroup --name $WebAppName --src-path $siteZip --type zip
    if ($LASTEXITCODE -ne 0) { throw 'Web App diegimas nepavyko.' }

    Compress-Archive -Path (Join-Path $functionDir '*') -DestinationPath $functionZip
    az functionapp deployment source config-zip --resource-group $ResourceGroup --name $FunctionAppName --src $functionZip
    if ($LASTEXITCODE -ne 0) { throw 'Function App diegimas nepavyko.' }

    # Tikriname ir health, ir puslapį, kuris iš tiesų įrašo žurnalą.
    foreach ($endpoint in @('health.asp', 'default.asp')) {
        $ready = $false
        for ($attempt = 1; $attempt -le 6; $attempt++) {
            try {
                $response = Invoke-WebRequest -Uri "https://$WebAppName.azurewebsites.net/$endpoint" -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
                $ready = $response.StatusCode -eq 200
            } catch { $ready = $false }
            if ($ready) { break }
            if ($attempt -lt 6) { Start-Sleep -Seconds 10 }
        }
        if (-not $ready) { throw "Svetainės patikra nepavyko: $endpoint" }
    }
    Write-Host "[OK] Svetainė ir funkcijos kodas įdiegti. Archyvavimą patikrinkite po Timer paleidimo." -ForegroundColor Green
} finally {
    foreach ($archive in @($siteZip, $functionZip)) {
        if (Test-Path -LiteralPath $archive) { Remove-Item -LiteralPath $archive -Force }
    }
}
