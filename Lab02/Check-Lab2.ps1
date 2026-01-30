# --- 1. UŽKRAUNAME BENDRAS FUNKCIJAS ---
try {
    irm "https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/configs/common.ps1" | iex
} catch {
    Write-Error "Nepavyko užkrauti bazinių funkcijų (common.ps1)."
    exit
}

# --- 2. INICIJUOJAME DARBĄ ---
$Setup = Initialize-Lab -LocalConfigUrl "https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/Lab02/Check-Lab2-config.json"
$LocCfg = $Setup.LocalConfig

# --- 3. DUOMENŲ RINKIMAS ---

# A. Randame Resursų grupę
$targetRG = Get-AzResourceGroup | Where-Object { $_.ResourceGroupName -match $LocCfg.ResourceGroupPattern } | Select-Object -First 1

if ($targetRG) {
    $rgText  = "[OK] - $($targetRG.ResourceGroupName)"
    $rgColor = "Green"
} else {
    $rgText  = "[KLAIDA] - Nerasta grupė '$($LocCfg.ResourceGroupPattern)...'"
    $rgColor = "Red"
}

# B. Tikriname resursus
$resourceResults = @()

# 1. Pirmas elementas - Resursų Grupė
$resourceResults += [PSCustomObject]@{
    Name  = "Resursų grupė"
    Text  = $rgText
    Color = $rgColor
}

# 2. Kiti resursai
if ($targetRG) {
    $allResources = Get-AzResource -ResourceGroupName $targetRG.ResourceGroupName
    
    foreach ($req in $LocCfg.RequiredResources) {
        $found = $allResources | Where-Object { $_.ResourceType -eq $req.Type } | Select-Object -First 1
        
        if ($found) {
            # --- FORMUOJAME PAPILDOMĄ INFO (Regionas, SKU) ---
            $extraInfo = ""
            
            # Regionas (visada rodomas)
            $region = $found.Location
            
            # SKU / Kaina (jei yra, pvz. Standard_LRS)
            if ($found.Sku -and $found.Sku.Name) {
                $extraInfo = " [$($found.Sku.Name)]"
            }
            
            # Galutinis tekstas: [OK] - Vardas (Regionas) [SKU]
            $finalText = "[OK] - $($found.Name) ($region)$extraInfo"
            
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
    foreach ($req in $LocCfg.RequiredResources) {
        $resourceResults += [PSCustomObject]@{
            Name  = $req.Name
            Text  = "[KLAIDA] - Nėra resursų grupės"
            Color = "Gray"
        }
    }
}

# --- 4. GALUTINIS REZULTATAS ---
$date = Get-Date -Format "yyyy-MM-dd HH:mm"

Write-Host "`n--- GALUTINIS REZULTATAS (Padarykite nuotrauką) ---" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Gray
Write-Host "$($Setup.HeaderTitle)"
Write-Host "$($LocCfg.LabName)" -ForegroundColor Yellow
Write-Host "Data: $date"
Write-Host "Studentas: $($Setup.StudentEmail)"
Write-Host "==================================================" -ForegroundColor Gray

$i = 1
foreach ($res in $resourceResults) {
    $label = "$i. $($res.Name):"
    
    # Lygiavimas (plotis 35 + apsauga)
    $targetWidth = 35
    $neededSpaces = $targetWidth - $label.Length
    if ($neededSpaces -lt 1) { $neededSpaces = 1 }
    $padding = " " * $neededSpaces
    
    Write-Host "$label$padding" -NoNewline
    Write-Host $res.Text -ForegroundColor $res.Color
    $i++
}

Write-Host "==================================================" -ForegroundColor Gray
Write-Host ""