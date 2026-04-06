# ... (Jūsų esamas Web App diegimas viršuje) ...
# iki 4. Tikrinimas (Healthcheck) eilutės. Nuo čia viską triname iki galo ir įkeliame naują kodą

# 4. Tikrinimas (Atnaujinta Healthcheck dalis)
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

