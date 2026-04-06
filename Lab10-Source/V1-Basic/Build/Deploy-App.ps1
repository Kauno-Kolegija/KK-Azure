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

Write-Host "--- PRADEDAMAS DIEGIMAS (Be HealthCheck failo) ---" -ForegroundColor Cyan

# 1. Paruošiame failus siuntimui (Dinaminis būdas)
Write-Host "Ieškoma .asp failų kataloge: $SourceDir" -ForegroundColor Yellow

# Randame visus failus, kurie baigiasi .asp
$filesToZip = Get-ChildItem -Path $SourceDir -Filter "*.asp" | Select-Object -ExpandProperty FullName

# Patikriname, ar radome bent vieną failą
if ($filesToZip.Count -eq 0) {
    Write-Error "KLAIDA: Kataloge '$SourceDir' nerasta jokių .asp failų!"
    return
}

# Parodome, ką radome (kad būtų aišku)
Write-Host "Rasta failų archyvavimui: $($filesToZip.Count)" -ForegroundColor Gray
$filesToZip | ForEach-Object { Write-Host " + $(Split-Path $_ -Leaf)" -ForegroundColor DarkGray }

# Jei senas zip yra - triname
if (Test-Path $ZipPath) { Remove-Item $ZipPath -Force }

# Kuriame archyvą iš surastų failų sąrašo
Compress-Archive -Path $filesToZip -DestinationPath $ZipPath -Force

# 2. Siunčiame į Web App
Write-Host "Siunčiamas kodas į serverį $WebAppName..." -ForegroundColor Magenta
az webapp deploy --resource-group $ResourceGroup --name $WebAppName --src-path $ZipPath --type zip

# 3. Išvalome šiukšles
Remove-Item $ZipPath -Force

# 4. Tikrinimas (Healthcheck)
Write-Host "Laukiama serverio starto (10s)..." -ForegroundColor Cyan
Start-Sleep -Seconds 10

# --- PAKEITIMAS 2: Tikriname pagrindinį puslapį, o ne health.asp ---
$MainUrl = "https://$WebAppName.azurewebsites.net/default.asp"

try {
    $response = Invoke-WebRequest -Uri $MainUrl -UseBasicParsing -ErrorAction Stop
    
    # Tikriname, ar serveris grąžino 200 OK
    if ($response.StatusCode -eq 200) {
        Write-Host "✅ SĖKMĖ! Serveris veikia." -ForegroundColor Green
        Write-Host "Svetainė: $MainUrl" -ForegroundColor Green
    }
}
catch {
    Write-Host "❌ KLAIDA: Serveris nepasiekiamas ($MainUrl)" -ForegroundColor Red
    Write-Host "Klaidos detalės: $_" -ForegroundColor DarkRed
}
