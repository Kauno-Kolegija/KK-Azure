param(
    [Parameter(Mandatory=$true)]
    [string]$ResourceGroup,

    [Parameter(Mandatory=$true)]
    [string]$WebAppName,
    
    [Parameter(Mandatory=$true)]
    [string]$StorageAccount
)

$ScriptDir = $PSScriptRoot
$SourceDir = Join-Path -Path $ScriptDir -ChildPath "..\Source"
$ZipPath   = Join-Path -Path $ScriptDir -ChildPath "site.zip"

Write-Host "--- PRADEDAMAS DIEGIMAS ---" -ForegroundColor Cyan

# 1. Paruošiame failus siuntimui
Write-Host "Pakuojama svetainė iš: $SourceDir" -ForegroundColor Yellow

# Patikriname, ar failai tikrai yra
if (-not (Test-Path "$SourceDir\default.asp")) {
    Write-Error "KLAIDA: Nerastas failas '$SourceDir\default.asp'. Patikrinkite katalogų struktūrą!"
    return
}

# Surenkame failus su pilnais keliais
$filesToZip = @(
    Join-Path $SourceDir "default.asp"
    Join-Path $SourceDir "health.asp"
)

# Jei senas zip yra - triname
if (Test-Path $ZipPath) { Remove-Item $ZipPath -Force }

# Kuriame archyvą
Compress-Archive -Path $filesToZip -DestinationPath $ZipPath -Force

# 2. Siunčiame į Web App
Write-Host "Siunčiamas kodas į serverį $WebAppName..." -ForegroundColor Magenta
az webapp deploy --resource-group $ResourceGroup --name $WebAppName --src-path $ZipPath --type zip

# 3. Išvalome šiukšles
Remove-Item $ZipPath -Force

# 4. Healthcheck
Write-Host "Laukiama serverio starto (10s)..." -ForegroundColor Cyan
Start-Sleep -Seconds 10

$HealthUrl = "https://$WebAppName.azurewebsites.net/health.asp"
try {
    $response = Invoke-WebRequest -Uri $HealthUrl -UseBasicParsing -ErrorAction Stop
    if ($response.StatusCode -eq 200) {
        Write-Host "✅ SĖKMĖ! Serveris veikia." -ForegroundColor Green
        Write-Host "Svetainė: https://$WebAppName.azurewebsites.net/default.asp" -ForegroundColor Green
    }
}
catch {
    Write-Host "❌ KLAIDA: Serveris nepasiekiamas ($HealthUrl)" -ForegroundColor Red
    Write-Host "Klaidos detalės: $_" -ForegroundColor DarkRed
}

# --- NAUJA DALIS: FUNCTION APP DIEGIMAS ---
$FunctionAppName = "func-$WebAppName" # Jei pavadinote taip pat kaip bicep faile
$FuncSourceDir = Join-Path -Path $ScriptDir -ChildPath "..\Source\Functions"
$FuncZipPath   = Join-Path -Path $ScriptDir -ChildPath "func.zip"

Write-Host "`n--- FUNCTION APP DIEGIMAS ---" -ForegroundColor Cyan
Write-Host "Pakuojama funkcija iš: $FuncSourceDir"

if (Test-Path $FuncZipPath) { Remove-Item $FuncZipPath -Force }
Compress-Archive -Path "$FuncSourceDir\*" -DestinationPath $FuncZipPath -Force

Write-Host "Siunčiama į $FunctionAppName..." -ForegroundColor Magenta

# Function App irgi naudoja zip deploy
az functionapp deployment source config-zip --resource-group $ResourceGroup --name $FunctionAppName --src $FuncZipPath

Write-Host "✅ Funkcija įdiegta!" -ForegroundColor Green
