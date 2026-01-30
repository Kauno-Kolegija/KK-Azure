# --- 1. UŽKRAUNAME BENDRAS FUNKCIJAS ---
try {
    irm "https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/configs/common.ps1" | iex
} catch {
    Write-Error "Nepavyko užkrauti bazinių funkcijų."
    exit
}

# --- 2. INICIJUOJAME DARBĄ ---
$Setup = Initialize-Lab -LocalConfigUrl "https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/Lab02/Check-Lab2-config.json"
$LocCfg = $Setup.LocalConfig

# --- 3. TYLUS TIKRINIMAS ---

# A. Randame Resursų grupę
$targetRG = Get-AzResourceGroup | Where-Object { $_.ResourceGroupName -match $LocCfg.ResourceGroupPattern } | Select-Object -First 1

if ($targetRG) {
    $allResources = Get-AzResource -ResourceGroupName $targetRG.ResourceGroupName
    
    foreach ($req in $LocCfg.RequiredResources) {
        $found = $allResources | Where-Object { $_.ResourceType -eq $req.Type } | Select-Object -First 1
        
        if ($found) {
            # --- PAKEITIMAS: Ištraukiame papildomą info ---
            $info = ""
            
            # Jei tai Storage - parodome SKU (pvz. Standard_LRS)
            if ($found.ResourceType -like "*storageAccounts*") {
                $sku = $found.Sku.Name
                $info = "[$sku]"
            }
            
            # Suformuojame tekstą: [OK] - Vardas (Regionas) [Papildoma info]
            $finalText = "[OK] - $($found.Name) ($($found.Location)) $info"
            
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
    $rgText  = "[KLAIDA] - Nerasta grupė '$($LocCfg.ResourceGroupPattern)...'"
    $rgColor = "Red"
}

# B. Tikriname resursus
$resourceResults = @()

# RG visada pirmas
$resourceResults += [PSCustomObject]@{
    Name  = "Resursų grupė"
    Text  = $rgText
    Color = $rgColor
}

if ($targetRG) {
    $allResources = Get-AzResource -ResourceGroupName $targetRG.ResourceGroupName
    
    foreach ($req in $LocCfg.RequiredResources) {
        $found = $allResources | Where-Object { $_.ResourceType -eq $req.Type } | Select-Object -First 1
        
        if ($found) {
            $resourceResults += [PSCustomObject]@{
                Name  = $req.Name
                Text  = "[OK] - $($found.Name)"
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

# Čia pakeista: Lab pavadinimas atskirai ir geltonai
Write-Host "$($LocCfg.LabName)" -ForegroundColor Yellow

Write-Host "Data: $date"
Write-Host "Studentas: $($Setup.StudentEmail)"
Write-Host "==================================================" -ForegroundColor Gray

# Dinaminis išvedimas
$i = 1
foreach ($res in $resourceResults) {
    $label = "$i. $($res.Name):"
    
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