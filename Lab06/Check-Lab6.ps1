# --- VERSIJOS KONTROLĖ ---
$ScriptVersion = "LAB 6 TIKRINIMAS: Storage, Security & Content (Diamond v2)"
Clear-Host
Write-Host "--------------------------------------------------"
Write-Host $ScriptVersion -ForegroundColor Magenta
Write-Host "Vykdoma pilna patikra (Infrastruktūra + Turinys)..."
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

# A. Resursų Grupės
$labRGs = Get-AzResourceGroup | Where-Object { $_.ResourceGroupName -match "RG-LAB06" }
if ($labRGs.Count -ge 1) {
    $rgText = "[OK] - Rasta resursų grupė(ės)"
    $rgColor = "Green"
} else {
    $rgText = "[KLAIDA] - Nerasta grupė RG-LAB06..."
    $rgColor = "Red"
}
$resourceResults += [PSCustomObject]@{ Name = "Resursų grupės"; Text = $rgText; Color = $rgColor }

# B. Storage Account
$storage = Get-AzStorageAccount | Where-Object { ($_.ResourceGroupName -match "RG-LAB06") -and ($_.StorageAccountName -match "store") } | Select-Object -First 1

if ($storage) {
    # 1. Access Tier
    if ($storage.AccessTier -eq "Cool") {
        $tierText = "[OK] - Nustatyta 'Cool' pakopa"
        $tierColor = "Green"
    } else {
        $tierText = "[DĖMESIO] - Rasta '$($storage.AccessTier)', o turėtų būti 'Cool'"
        $tierColor = "Yellow"
    }
    $resourceResults += [PSCustomObject]@{ Name = "Storage Tier"; Text = $tierText; Color = $tierColor }

    # 2. Static Website
    if ($storage.PrimaryEndpoints.Web) {
        $webText = "[OK] - Static Website įjungtas"
        $webColor = "Green"
    } else {
        $webText = "[TRŪKSTA] - Static Website funkcija išjungta"
        $webColor = "Red"
    }
    $resourceResults += [PSCustomObject]@{ Name = "Statinė svetainė"; Text = $webText; Color = $webColor }

    # 3. File Share (NAUJA: Tikriname ar sukurtas diskas)
    # Naudojame RM komandą, kad apeitume ugniasienę
    $share = Get-AzRmStorageShare -ResourceGroupName $storage.ResourceGroupName -StorageAccountName $storage.StorageAccountName -Name "imones-duomenys" -ErrorAction SilentlyContinue
    
    if ($share) {
        $shareText = "[OK] - Rastas tinklo diskas 'imones-duomenys'"
        $shareColor = "Green"
    } else {
        $shareText = "[TRŪKSTA] - Nesukurtas File Share 'imones-duomenys'"
        $shareColor = "Red"
    }
    $resourceResults += [PSCustomObject]@{ Name = "Azure Files (Z:)"; Text = $shareText; Color = $shareColor }

    # 4. Blob Containers (NAUJA: Tikriname papildomus konteinerius)
    $contArch = Get-AzRmStorageContainer -ResourceGroupName $storage.ResourceGroupName -StorageAccountName $storage.StorageAccountName -Name "archyvas" -ErrorAction SilentlyContinue
    $contPriv = Get-AzRmStorageContainer -ResourceGroupName $storage.ResourceGroupName -StorageAccountName $storage.StorageAccountName -Name "privatus" -ErrorAction SilentlyContinue

    if ($contArch -or $contPriv) {
        $blobText = "[OK] - Rasti papildomi konteineriai (Archyvas/Privatus)"
        $blobColor = "Green"
    } else {
        $blobText = "[TRŪKSTA] - Nerasti konteineriai 'archyvas' arba 'privatus'"
        $blobColor = "Red"
    }
    $resourceResults += [PSCustomObject]@{ Name = "Blob Konteineriai"; Text = $blobText; Color = $blobColor }

    # 5. SAUGUMAS (Firewall)
    if ($storage.NetworkRuleSet.DefaultAction -eq "Deny") {
        $fwText = "[OK] - Vieša prieiga blokuojama (Firewall Active)"
        $fwColor = "Green"
        
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

# C. Virtuali Mašina
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