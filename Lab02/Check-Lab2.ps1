# --- 1. UŽKRAUNAME BENDRAS FUNKCIJAS ---
try {
    irm "https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/configs/common.ps1" | iex
} catch {
    Write-Error "Nepavyko užkrauti bazinių funkcijų (common.ps1). Patikrinkite interneto ryšį."
    exit
}

# --- 2. INICIJUOJAME DARBĄ ---
# Ši funkcija (iš common.ps1) atsiunčia konfigūraciją, identifikuoja studentą ir parodo geltoną "Vykdoma..."
$Setup = Initialize-Lab -LocalConfigUrl "https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/Lab02/Check-Lab2-config.json"
$LocCfg = $Setup.LocalConfig

# --- 3. TYLUS TIKRINIMAS IR DUOMENŲ RINKIMAS ---

# A. Randame Resursų grupę
$targetRG = Get-AzResourceGroup | Where-Object { $_.ResourceGroupName -match $LocCfg.ResourceGroupPattern } | Select-Object -First 1

if ($targetRG) {
    $rgText  = "[OK] - $($targetRG.ResourceGroupName)"
    $rgColor = "Green"
} else {
    $rgText  = "[KLAIDA] - Nerasta grupė pagal šabloną '$($LocCfg.ResourceGroupPattern)...'"
    $rgColor = "Red"
}

# B. Tikriname resursus
$resourceResults = @()

# 1. Pirmas elementas visada yra Resursų Grupė
$resourceResults += [PSCustomObject]@{
    Name  = "Resursų grupė"
    Text  = $rgText
    Color = $rgColor
}

# 2. Tikriname kitus resursus (jei grupė egzistuoja)
if ($targetRG) {
    # Paimame visus resursus toje grupėje
    $allResources = Get-AzResource -ResourceGroupName $targetRG.ResourceGroupName
    
    foreach ($req in $LocCfg.RequiredResources) {
        # Ieškome resurso pagal tipą
        $found = $allResources | Where-Object { $_.ResourceType -eq $req.Type } | Select-Object -First 1
        
        if ($found) {
            # --- Papildomos informacijos formavimas ---
            $extraInfo = ""
            
            # Jei resursas turi SKU (pvz. Storage: Standard_LRS), pridedame jį
            if ($found.Sku -and $found.Sku.Name) {
                $extraInfo = " [$($found.Sku.Name)]"
            }
            
            # Formatas: [OK] - Vardas (Regionas) [SKU]
            # Pvz.: [OK] - mantas-storage (northeurope) [Standard_LRS]
            $finalText = "[OK] - $($found.Name) ($($found.Location))$extraInfo"
            
            $resourceResults += [PSCustomObject]@{
                Name  = $req.Name
                Text  = $finalText
                Color = "Green"
            }
        } else {
            $resourceResults += [PSCustomObject]@{
                Name  = $req.Name
                Text  = "[TRŪKSTA] - Nerastas resursas"
                Color = "Red"
            }
        }
    }
} else {
    # Jei grupės nėra, visi kiti resursai automatiškai žymimi kaip klaida
    foreach ($req in $LocCfg.RequiredResources) {
        $resourceResults += [PSCustomObject]@{
            Name  = $req.Name
            Text  = "[KLAIDA] - Nėra resursų grupės"
            Color = "Gray"
        }
    }
}

# --- 4. GALUTINIS REZULTATAS (Išvedimas į ekraną) ---
$date = Get-Date -Format "yyyy-MM-dd HH:mm"

Write-Host "`n--- GALUTINIS REZULTATAS (Padarykite nuotrauką) ---" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Gray
Write-Host "$($Setup.HeaderTitle)"

# Lab Pavadinimas - Geltonas
Write-Host "$($LocCfg.LabName)" -ForegroundColor Yellow

Write-Host "Data: $date"
Write-Host "Studentas: $($Setup.StudentEmail)"
Write-Host "==================================================" -ForegroundColor Gray

# Dinaminis sąrašo išvedimas
$i = 1
foreach ($res in $resourceResults) {
    $label = "$i. $($res.Name):"
    
    # Lygiavimo logika (kad stulpeliai būtų tiesūs)
    $targetWidth = 35
    $neededSpaces = $targetWidth - $label.Length
    if ($neededSpaces -lt 1) { $neededSpaces = 1 } # Apsauga nuo neigiamų skaičių
    $padding = " " * $neededSpaces
    
    # Išvedame eilutę
    Write-Host "$label$padding" -NoNewline
    Write-Host $res.Text -ForegroundColor $res.Color
    $i++
}

Write-Host "==================================================" -ForegroundColor Gray
Write-Host ""