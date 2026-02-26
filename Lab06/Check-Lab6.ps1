# --- VERSIJOS KONTROLĖ ---
$ScriptVersion = "LAB 06: Saugyklos paslaugos (JSON Dinaminė Patikra)"
Clear-Host
Write-Host "--------------------------------------------------"
Write-Host $ScriptVersion -ForegroundColor Magenta
Write-Host "--------------------------------------------------"

# --- 1. UŽKRAUNAME BENDRAS FUNKCIJAS ---
try {
    irm "https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/configs/common.ps1" | iex
} catch {
    Write-Error "Nepavyko užkrauti bazinių funkcijų."
    exit
}

# --- 2. INICIJUOJAME DARBĄ (Skaitome JSON failą) ---
# DĖMESIO: Pakeiskite šią nuorodą į savo tikrąją Check-Lab6-config.json repozitorijoje
$ConfigUrl = "https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/Lab06/Check-Lab6-config.json"

try {
    $Setup = Initialize-Lab -LocalConfigUrl $ConfigUrl
    $LocCfg = $Setup.LocalConfig
} catch {
    Write-Error "Nepavyko užkrauti konfigūracijos iš $ConfigUrl"
    exit
}

$CurrentIdentity = az ad signed-in-user show --query userPrincipalName -o tsv
if (-not $CurrentIdentity) { $CurrentIdentity = "Studentas" }

$resourceResults = @()

# --- 3. RESURSŲ GRUPĖS PATIKRA (Pagal JSON) ---
$rgPattern = $LocCfg.ResourceGroupPattern
$labRG = Get-AzResourceGroup | Where-Object { $_.ResourceGroupName -match $rgPattern } | Select-Object -First 1

if ($labRG) {
    $resourceResults += [PSCustomObject]@{ Name = "Resursų grupė"; Text = "[OK] - Rastas $($labRG.ResourceGroupName)"; Color = "Green" }
    
    # --- 4. REIKALAUJAMŲ RESURSŲ PATIKRA (Pagal JSON RequiredResources sąrašą) ---
    if ($LocCfg.RequiredResources) {
        foreach ($reqRes in $LocCfg.RequiredResources) {
            $resType = $reqRes.Type
            $resName = $reqRes.Name
            
            # Formatuojame gražų pavadinimą (pvz. iš Microsoft.Storage/storageAccounts padarome storageAccounts)
            $shortType = ($resType -split '/')[-1] 
            
            # Ieškome resurso pagal tipą ir pavadinimą
            $foundResource = Get-AzResource -ResourceGroupName $labRG.ResourceGroupName -ResourceType $resType -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $resName } | Select-Object -First 1
            
            if ($foundResource) {
                $resourceResults += [PSCustomObject]@{ Name = "$shortType"; Text = "[OK] - Rastas ($($foundResource.Name))"; Color = "Green" }
            } else {
                $resourceResults += [PSCustomObject]@{ Name = "$shortType"; Text = "[KLAIDA] - Nerastas resursas pavadinimu '*$resName*'"; Color = "Red" }
            }
        }
    } else {
        $resourceResults += [PSCustomObject]@{ Name = "Konfigūracija"; Text = "[ĮSPĖJIMAS] - JSON faile nerasta 'RequiredResources' sąrašo"; Color = "Yellow" }
    }

} else {
     $resourceResults += [PSCustomObject]@{ Name = "Resursų grupė"; Text = "[KLAIDA] - Nerasta grupė pagal šabloną '$rgPattern'"; Color = "Red" }
}

# --- 5. IŠVEDIMAS (Ataskaitai) ---
$date = Get-Date -Format "yyyy-MM-dd HH:mm"

Write-Host "`n--- GALUTINIS REZULTATAS ---" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Gray
if ($Setup.HeaderTitle) { Write-Host "$($Setup.HeaderTitle)" }
Write-Host "$($LocCfg.LabName)" -ForegroundColor Yellow
Write-Host "Data: $date"
Write-Host "Studentas: $CurrentIdentity"
Write-Host "==================================================" -ForegroundColor Gray

foreach ($res in $resourceResults) {
    $label = "$($res.Name):"
    $targetWidth = 25
    $neededSpaces = $targetWidth - $label.Length
    if ($neededSpaces -lt 1) { $neededSpaces = 1 }
    $padding = " " * $neededSpaces
    Write-Host "$label$padding" -NoNewline
    Write-Host $res.Text -ForegroundColor $res.Color
}
Write-Host "==================================================" -ForegroundColor Gray
Write-Host ""