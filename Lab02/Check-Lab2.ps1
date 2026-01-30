# --- KONFIGŪRACIJOS GAVIMAS ---
# 1. Bendra konfigūracija (Global)
$globalUrl = "https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/configs/global.json"
# 2. Šio laboratorinio konfigūracija (Local)
$localUrl  = "https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/Lab02/Check-Lab2-config.json"


[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# --- DUOMENŲ GAVIMAS ---
try {
    $globalConfig = Invoke-RestMethod -Uri $globalUrl -ErrorAction Stop
    $localConfig  = Invoke-RestMethod -Uri $localUrl -ErrorAction Stop
} catch {
    Write-Error "Nepavyko atsisiųsti konfigūracijos."
    exit
}

# --- KINTAMIEJI ---
$labTitle     = $localConfig.LabName
$rgPattern    = $localConfig.ResourceGroupPattern
$resourcesReq = $localConfig.RequiredResources
$headerTitle  = "$($globalConfig.KaunoKolegija) | $($globalConfig.ModuleName)"

Clear-Host
Write-Host "--- $headerTitle ---" -ForegroundColor Cyan
Write-Host "--- $labTitle ---" -ForegroundColor Yellow
Write-Host "Vykdoma resursų paieška..." -ForegroundColor Gray

# 1. IDENTIFIKACIJA
$context = Get-AzContext
if (-not $context) { Write-Error "Neprisijungta!"; exit }
$studentEmail = if ($env:ACC_USER_NAME) { $env:ACC_USER_NAME } else { $context.Account.Id }

# 2. RESURSŲ GRUPĖS PAIEŠKA
$targetRG = Get-AzResourceGroup | Where-Object { $_.ResourceGroupName -match $rgPattern } | Select-Object -First 1

if ($targetRG) {
    Write-Host "`n1. Resursų grupė (${rgPattern}...):" -NoNewline
    Write-Host " RASTA ($($targetRG.ResourceGroupName))" -ForegroundColor Green
    $rgStatus = "OK ($($targetRG.ResourceGroupName))"
    $rgName = $targetRG.ResourceGroupName
} else {
    Write-Host "`n1. Resursų grupė (${rgPattern}...):" -NoNewline
    Write-Host " NERASTA" -ForegroundColor Red
    Write-Host "   -> Būtina sukurti grupę prasidedančia 'RG-LAB02-'" -ForegroundColor Yellow
    $rgStatus = "NERASTA"
    $rgName = $null
}

# 3. RESURSŲ TIKRINIMAS GRUPĖJE
$resReport = ""
if ($rgName) {
    # Gauname visus resursus toje grupėje
    $allResources = Get-AzResource -ResourceGroupName $rgName
    
    foreach ($req in $resourcesReq) {
        # Ieškome ar yra toks resursas
        $found = $allResources | Where-Object { $_.ResourceType -eq $req.Type } | Select-Object -First 1
        
        Write-Host "2. $($req.Name):" -NoNewline
        if ($found) {
            Write-Host " RASTA ($($found.Name))" -ForegroundColor Green
            $resReport += "$($req.Name): OK`n"
            
            # Regiono perspėjimas (jei labai toli)
            if ($found.Location -notin $localConfig.AllowedRegions) {
                Write-Host "   -> Dėmesio: Regionas '$($found.Location)' nėra standartinis, bet užskaityta." -ForegroundColor DarkGray
            }
        } else {
            Write-Host " NERASTA" -ForegroundColor Red
            $resReport += "$($req.Name): TRŪKSTA`n"
        }
    }
} else {
    $resReport = "Nėra Resursų grupės - patikra negalima."
}

# --- ATASKAITA ---
$date = Get-Date -Format "yyyy-MM-dd HH:mm"
$report = @"
==================================================
$headerTitle
$labTitle
Data: $date
Studentas: $studentEmail
==================================================
1. Resursų grupė: $rgStatus
--------------------------------------------------
$resReport
==================================================
"@

Write-Host "`n--- GALUTINIS REZULTATAS ---" -ForegroundColor Cyan
Write-Host $report
Write-Host ""