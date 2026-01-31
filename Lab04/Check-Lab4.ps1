# --- 1. UŽKRAUNAME BENDRAS FUNKCIJAS ---
try {
    irm "https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/configs/common.ps1" | iex
} catch {
    Write-Error "Nepavyko užkrauti bazinių funkcijų (common.ps1)."
    exit
}

# --- 2. INICIJUOJAME DARBĄ ---
$Setup = Initialize-Lab -LocalConfigUrl "https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/Lab03/Check-Lab3-config.json"
$LocCfg = $Setup.LocalConfig

# --- 2. INICIJUOJAME DARBĄ ---
# Šiam darbui konfigūraciją generuojame dinamiškai, nes studentai naudoja savo vardus RG pavadinime
$CurrentIdentity = az ad signed-in-user show --query userPrincipalName -o tsv
if (-not $CurrentIdentity) { $CurrentIdentity = "Studentas" }

# Bandome atspėti RG pavadinimą (RG04-*)
$targetRG = Get-AzResourceGroup | Where-Object { $_.ResourceGroupName -like "RG04-*" } | Sort-Object LastModifiedTime -Descending | Select-Object -First 1

# --- 3. DUOMENŲ RINKIMAS ---

$resourceResults = @()

# 1. Resursų Grupė
if ($targetRG) {
    $rgText  = "[OK] - $($targetRG.ResourceGroupName) ($($targetRG.Location))"
    $rgColor = "Green"
} else {
    $rgText  = "[KLAIDA] - Nerasta grupė, prasidedanti 'RG04-...'"
    $rgColor = "Red"
}
$resourceResults += [PSCustomObject]@{ Name = "Resursų grupė"; Text = $rgText; Color = $rgColor }

if ($targetRG) {
    # 2. Virtualus Tinklas (VNet)
    $vnet = Get-AzVirtualNetwork -ResourceGroupName $targetRG.ResourceGroupName | Select-Object -First 1
    if ($vnet) {
        $vnetText = "[OK] - $($vnet.Name) ($( ($vnet.AddressSpace.AddressPrefixes) -join ', ' ))"
        $vnetColor = "Green"
    } else {
        $vnetText = "[TRŪKSTA] - Nerastas Virtualus Tinklas (VNet)"
        $vnetColor = "Red"
    }
    $resourceResults += [PSCustomObject]@{ Name = "Virtualus Tinklas"; Text = $vnetText; Color = $vnetColor }

    # 3. Load Balancer (Sunkiausia dalis)
    $lb = Get-AzLoadBalancer -ResourceGroupName $targetRG.ResourceGroupName | Select-Object -First 1
    if ($lb) {
        $lbText = "[OK] - $($lb.Name) (Frontend IP: $($lb.FrontendIpConfigurations.Count))"
        $lbColor = "Green"
    } else {
        $lbText = "[TRŪKSTA] - Nerastas Load Balancer (NLB)"
        $lbColor = "Red"
    }
    $resourceResults += [PSCustomObject]@{ Name = "Load Balancer"; Text = $lbText; Color = $lbColor }

    # 4. Availability Set
    $avSet = Get-AzAvailabilitySet -ResourceGroupName $targetRG.ResourceGroupName | Select-Object -First 1
    if ($avSet) {
        $avText = "[OK] - $($avSet.Name)"
        $avColor = "Green"
    } else {
        $avText = "[DĖMESIO] - Nerastas Availability Set (Būtina 'Standard' LB veikimui)"
        $avColor = "Yellow"
    }
    $resourceResults += [PSCustomObject]@{ Name = "Availability Set"; Text = $avText; Color = $avColor }

    # 5. Virtualios mašinos (VMs)
    $vms = Get-AzVM -ResourceGroupName $targetRG.ResourceGroupName
    $vmCount = $vms.Count
    
    if ($vmCount -ge 2) {
        # Tikriname ar jos yra Availability Set'e
        $inAvSet = 0
        foreach ($vm in $vms) {
            if ($vm.AvailabilitySetReference) { $inAvSet++ }
        }

        if ($inAvSet -eq $vmCount) {
            $vmText = "[OK] - Rasta VM: $vmCount (Visos yra Availability Set)"
            $vmColor = "Green"
        } else {
            $vmText = "[DĖMESIO] - Rasta VM: $vmCount, bet tik $inAvSet yra Availability Set'e"
            $vmColor = "Yellow"
        }
    } elseif ($vmCount -eq 1) {
        $vmText = "[TRŪKSTA] - Rasta tik 1 VM (Reikia 2)"
        $vmColor = "Yellow"
    } else {
        $vmText = "[TRŪKSTA] - Nerasta virtualių serverių"
        $vmColor = "Red"
    }
    $resourceResults += [PSCustomObject]@{ Name = "Serveriai (VM)"; Text = $vmText; Color = $vmColor }
}

# --- 4. IŠVEDIMAS ---
$date = Get-Date -Format "yyyy-MM-dd HH:mm"

Write-Host "`n--- GALUTINIS REZULTATAS (Padarykite nuotrauką) ---" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Gray
Write-Host "KAUNO KOLEGIJA | LAB 4: Networking"
Write-Host "Data: $date"
Write-Host "Vartotojas: $CurrentIdentity"
Write-Host "==================================================" -ForegroundColor Gray

$i = 1
foreach ($res in $resourceResults) {
    $label = "$i. $($res.Name):"
    
    $targetWidth = 30
    $neededSpaces = $targetWidth - $label.Length
    if ($neededSpaces -lt 1) { $neededSpaces = 1 }
    $padding = " " * $neededSpaces
    
    Write-Host "$label$padding" -NoNewline
    Write-Host $res.Text -ForegroundColor $res.Color
    $i++
}

Write-Host "==================================================" -ForegroundColor Gray
if (-not $lb) {
    Write-Host "Patarimas: Jei nerandate Load Balancer, patikrinkite 'az network lb create' komandą." -ForegroundColor DarkGray
}
Write-Host ""