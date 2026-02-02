# --- VERSIJOS KONTROLĖ ---
$ScriptVersion = "LAB 6 TIKRINIMAS: Storage & Security (Firewall-Aware)"
Clear-Host
Write-Host "--------------------------------------------------"
Write-Host $ScriptVersion -ForegroundColor Magenta
Write-Host "Vykdoma patikra (Ignoruojant Data Plane blokavimą)..."
Write-Host "--------------------------------------------------"

# --- 1. UŽKRAUNAME BENDRAS FUNKCIJAS ---
try {
    irm "https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/configs/common.ps1" | iex
} catch {
    Write-Error "Nepavyko užkrauti bazinių funkcijų."
    exit
}

# --- 2. INICIJUOJAME DARBĄ ---
$ConfigUrl = "https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/Lab06/Check-Lab6-config.json"
try {
    $Setup = Initialize-Lab -LocalConfigUrl $ConfigUrl
    $LocCfg = $Setup.LocalConfig
} catch {
    $LocCfg = @{ LabName = "Azure Storage Lab" }
}

$CurrentIdentity = az ad signed-in-user show --query userPrincipalName -o tsv
if (-not $CurrentIdentity) { $CurrentIdentity = "Studentas" }

# --- 3. DUOMENŲ RINKIMAS ---
$resourceResults = @()

# A. Resursų Grupės (Gali būti 1 arba 2 dėl Move operacijos)
$labRGs = Get-AzResourceGroup | Where-Object { $_.ResourceGroupName -match "RG-LAB06" }
if ($labRGs.Count -ge 1) {
    $rgText = "[OK] - Rasta resursų grupė(ės)"
    $rgColor = "Green"
} else {
    $rgText = "[KLAIDA] - Nerasta grupė RG-LAB06..."
    $rgColor = "Red"
}
$resourceResults += [PSCustomObject]@{ Name = "Resursų grupės"; Text = $rgText; Color = $rgColor }

# B. Storage Account (Pagrindinis resursas)
# Ieškome bet kurios saugyklos, kurios pavadinime yra "store" ir ji yra LAB06 grupėse
$storage = Get-AzStorageAccount | Where-Object { ($_.ResourceGroupName -match "RG-LAB06") -and ($_.StorageAccountName -match "store") } | Select-Object -First 1

if ($storage) {
    # 1. Access Tier (Cool)
    if ($storage.AccessTier -eq "Cool") {
        $tierText = "[OK] - Nustatyta 'Cool' pakopa"
        $tierColor = "Green"
    } else {
        $tierText = "[DĖMESIO] - Rasta '$($storage.AccessTier)', o turėtų būti 'Cool'"
        $tierColor = "Yellow"
    }
    $resourceResults += [PSCustomObject]@{ Name = "Storage Tier"; Text = $tierText; Color = $tierColor }

    # 2. Static Website (Tikriname per PrimaryEndpoints)
    if ($storage.PrimaryEndpoints.Web) {
        $webText = "[OK] - Static Website įjungtas"
        $webColor = "Green"
    } else {
        $webText = "[TRŪKSTA] - Static Website funkcija išjungta"
        $webColor = "Red"
    }
    $resourceResults += [PSCustomObject]@{ Name = "Statinė svetainė"; Text = $webText; Color = $webColor }

    # 3. SAUGUMAS (Firewall) - Tikriname Control Plane
    # DefaultAction 'Deny' reiškia, kad vieša prieiga užblokuota (Selected networks)
    if ($storage.NetworkRuleSet.DefaultAction -eq "Deny") {
        $fwText = "[OK] - Vieša prieiga blokuojama (Firewall Active)"
        $fwColor = "Green"
        
        # Tikriname ar pridėtas VNet
        if ($storage.NetworkRuleSet.VirtualNetworkRules.Count -gt 0) {
            $vnetText = "[OK] - Pridėta VNet taisyklė ($($storage.NetworkRuleSet.VirtualNetworkRules.Count))"
            $vnetColor = "Green"
        } else {
            $vnetText = "[KLAIDA] - Ugniasienė įjungta, bet VNet nepridėtas!"
            $vnetColor = "Red"
        }
    } else {
        $fwText = "[KLAIDA] - Vieša prieiga vis dar atvira (Allow All)"
        $fwColor = "Red"
        $vnetText = "-"
        $vnetColor = "Gray"
    }
    $resourceResults += [PSCustomObject]@{ Name = "Saugumas (Firewall)"; Text = $fwText; Color = $fwColor }
    if ($vnetText -ne "-") {
        $resourceResults += [PSCustomObject]@{ Name = "Saugumas (VNet)"; Text = $vnetText; Color = $vnetColor }
    }

} else {
    $resourceResults += [PSCustomObject]@{ Name = "Storage Account"; Text = "[TRŪKSTA] - Nerasta saugykla (*store*)"; Color = "Red" }
}

# C. Virtuali Mašina (Per ARM Template)
$vm = Get-AzVM | Where-Object { ($_.ResourceGroupName -match "RG-LAB06") -and ($_.Name -eq "VM-Storage") } | Select-Object -First 1

if ($vm) {
    $vmText = "[OK] - VM-Storage veikia ($($vm.Location))"
    $vmColor = "Green"
} else {
    $vmText = "[TRŪKSTA] - Nerastas serveris VM-Storage"
    $vmColor = "Red"
}
$resourceResults += [PSCustomObject]@{ Name = "Serveris (IaC)"; Text = $vmText; Color = $vmColor }


# --- 4. IŠVEDIMAS ---
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
    $targetWidth = 35
    $neededSpaces = $targetWidth - $label.Length
    if ($neededSpaces -lt 1) { $neededSpaces = 1 }
    $padding = " " * $neededSpaces
    Write-Host "$label$padding" -NoNewline
    Write-Host $res.Text -ForegroundColor $res.Color
}
Write-Host "==================================================" -ForegroundColor Gray
Write-Host ""