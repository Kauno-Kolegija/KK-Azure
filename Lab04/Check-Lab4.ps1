# --- VERSIJOS KONTROLĖ ---
$ScriptVersion = "LAB 4 TIKRINIMAS: Networking"
Clear-Host
Write-Host "--------------------------------------------------"
Write-Host $ScriptVersion -ForegroundColor Magenta
Write-Host "Vykdoma detali infrastruktūros patikra..."
Write-Host "--------------------------------------------------"

# --- 1. UŽKRAUNAME BENDRAS FUNKCIJAS ---
try {
    irm "https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/configs/common.ps1" | iex
} catch {
    Write-Error "Nepavyko užkrauti bazinių funkcijų (common.ps1)."
    exit
}

# --- 2. INICIJUOJAME DARBĄ ---
$Setup = Initialize-Lab -LocalConfigUrl "https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/Lab04/Check-Lab4-config.json"
$LocCfg = $Setup.LocalConfig

$CurrentIdentity = az ad signed-in-user show --query userPrincipalName -o tsv
if (-not $CurrentIdentity) { $CurrentIdentity = "Studentas" }

# --- 3. DUOMENŲ RINKIMAS ---

# Ieškome grupės pagal JSON konfigūraciją
$targetRG = Get-AzResourceGroup | Where-Object { $_.ResourceGroupName -match $LocCfg.ResourceGroupPattern } | Sort-Object LastModifiedTime -Descending | Select-Object -First 1

$resourceResults = @()

# A. Resursų Grupė
if ($targetRG) {
    $rgText  = "[OK] - $($targetRG.ResourceGroupName) ($($targetRG.Location))"
    $rgColor = "Green"
} else {
    $rgText  = "[KLAIDA] - Nerasta grupė pagal šabloną '$($LocCfg.ResourceGroupPattern)...'"
    $rgColor = "Red"
}
$resourceResults += [PSCustomObject]@{ Name = "Resursų grupė"; Text = $rgText; Color = $rgColor }

if ($targetRG) {
    # B. TINKLAS (VNET & SUBNET)
    $vnet = Get-AzVirtualNetwork -ResourceGroupName $targetRG.ResourceGroupName | Select-Object -First 1
    if ($vnet) {
        $vnetText = "[OK] - $($vnet.Name)"
        $vnetColor = "Green"
    } else {
        $vnetText = "[TRŪKSTA] - Nerastas VNet"
        $vnetColor = "Red"
    }
    $resourceResults += [PSCustomObject]@{ Name = "Virtualus Tinklas"; Text = $vnetText; Color = $vnetColor }

    # Tikriname Subnet (WebSubnet)
    if ($vnet) {
        $subnet = $vnet.Subnets | Where-Object { $_.Name -eq "WebSubnet" }
        if ($subnet) {
            $resourceResults += [PSCustomObject]@{ Name = " - Potinklis (Subnet)"; Text = "[OK] - WebSubnet (10.15.0.0/24)"; Color = "Green" }
        } else {
            $resourceResults += [PSCustomObject]@{ Name = " - Potinklis (Subnet)"; Text = "[TRŪKSTA] - Nerastas 'WebSubnet'"; Color = "Red" }
        }
    }

    # C. Network Security Group (NSG)
    $nsg = Get-AzNetworkSecurityGroup -ResourceGroupName $targetRG.ResourceGroupName | Select-Object -First 1
    if ($nsg) {
        $nsgText = "[OK] - $($nsg.Name)"
        $nsgColor = "Green"
    } else {
        $nsgText = "[TRŪKSTA] - Nerasta NSG"
        $nsgColor = "Red"
    }
    $resourceResults += [PSCustomObject]@{ Name = "Saugumo grupė (NSG)"; Text = $nsgText; Color = $nsgColor }

    if ($nsg) {
        # Tikriname taisykles (Port 80 ir 3389)
        $ruleWeb = $nsg.SecurityRules | Where-Object { $_.DestinationPortRange -contains "80" -and $_.Access -eq "Allow" }
        $ruleRDP = $nsg.SecurityRules | Where-Object { $_.DestinationPortRange -contains "3389" -and $_.Access -eq "Allow" }
        
        if ($ruleWeb) { 
            $resourceResults += [PSCustomObject]@{ Name = " - Taisyklė: WEB"; Text = "[OK] - Port 80 atidarytas"; Color = "Green" }
        } else {
            $resourceResults += [PSCustomObject]@{ Name = " - Taisyklė: WEB"; Text = "[TRŪKSTA] - Nėra taisyklės prievadui 80"; Color = "Red" }
        }
        
        if ($ruleRDP) { 
            $resourceResults += [PSCustomObject]@{ Name = " - Taisyklė: RDP"; Text = "[OK] - Port 3389 atidarytas"; Color = "Green" }
        } else {
            $resourceResults += [PSCustomObject]@{ Name = " - Taisyklė: RDP"; Text = "[TRŪKSTA] - Nėra taisyklės prievadui 3389"; Color = "Yellow" }
        }
    }

    # D. Public IPs
    $pips = Get-AzPublicIpAddress -ResourceGroupName $targetRG.ResourceGroupName
    if ($pips.Count -ge 3) {
        $pipText = "[OK] - Rasta IP adresų: $($pips.Count) (VMs + LB)"
        $pipColor = "Green"
    } else {
        $pipText = "[DĖMESIO] - Rasta tik $($pips.Count) IP adresai (Reikia min 3)"
        $pipColor = "Yellow"
    }
    $resourceResults += [PSCustomObject]@{ Name = "Vieši IP adresai"; Text = $pipText; Color = $pipColor }

    # E. LOAD BALANCER
    $lb = Get-AzLoadBalancer -ResourceGroupName $targetRG.ResourceGroupName | Select-Object -First 1
    if ($lb) {
        $lbText = "[OK] - $($lb.Name)"
        $lbColor = "Green"
    } else {
        $lbText = "[TRŪKSTA] - Nerastas Load Balancer"
        $lbColor = "Red"
    }
    $resourceResults += [PSCustomObject]@{ Name = "Load Balancer (LB)"; Text = $lbText; Color = $lbColor }

    if ($lb) {
        # Health Probe
        if ($lb.Probes.Count -gt 0) {
            $resourceResults += [PSCustomObject]@{ Name = " - LB Health Probe"; Text = "[OK] - Rasta ($($lb.Probes.Name))"; Color = "Green" }
        } else {
            $resourceResults += [PSCustomObject]@{ Name = " - LB Health Probe"; Text = "[TRŪKSTA] - Nėra sveikatos patikros"; Color = "Red" }
        }
        # Rules
        if ($lb.LoadBalancingRules.Count -gt 0) {
            $resourceResults += [PSCustomObject]@{ Name = " - LB Taisyklės"; Text = "[OK] - Rasta ($($lb.LoadBalancingRules.Name))"; Color = "Green" }
        } else {
            $resourceResults += [PSCustomObject]@{ Name = " - LB Taisyklės"; Text = "[TRŪKSTA] - Nėra balansavimo taisyklių"; Color = "Red" }
        }
    }

    # F. Availability Set
    $avSet = Get-AzAvailabilitySet -ResourceGroupName $targetRG.ResourceGroupName | Select-Object -First 1
    if ($avSet) {
        $resourceResults += [PSCustomObject]@{ Name = "Availability Set"; Text = "[OK] - $($avSet.Name)"; Color = "Green" }
    } else {
        $resourceResults += [PSCustomObject]@{ Name = "Availability Set"; Text = "[DĖMESIO] - Nerastas Availability Set"; Color = "Yellow" }
    }

    # G. Virtualios mašinos (VMs) + Tags
    $vms = Get-AzVM -ResourceGroupName $targetRG.ResourceGroupName
    $vmCount = $vms.Count
    
    if ($vmCount -ge 2) {
        # Availability Check
        $inAvSet = 0
        $tagged = 0
        foreach ($vm in $vms) {
            if ($vm.AvailabilitySetReference) { $inAvSet++ }
            # Tikriname ar yra bet kokie tagai
            if ($vm.Tags.Count -gt 0) { $tagged++ }
        }

        if ($inAvSet -eq $vmCount) {
            $vmText = "[OK] - Rasta VM: $vmCount (Visos Availability Set)"
            $vmColor = "Green"
        } else {
            $vmText = "[DĖMESIO] - Rasta VM: $vmCount, bet ne visos Availability Set"
            $vmColor = "Yellow"
        }
        
        # Tags Check
        if ($tagged -eq $vmCount) {
             $tagText = "[OK] - Serveriai sužymėti (Tags)"
             $tagColor = "Green"
        } else {
             $tagText = "[DĖMESIO] - Trūksta 'Tags' ant serverių"
             $tagColor = "Yellow"
        }

    } else {
        $vmText = "[TRŪKSTA] - Rasta tik $vmCount VM (Reikia 2)"
        $vmColor = "Red"
        $tagText = "---"
        $tagColor = "Gray"
    }
    $resourceResults += [PSCustomObject]@{ Name = "Serveriai (VM)"; Text = $vmText; Color = $vmColor }
    $resourceResults += [PSCustomObject]@{ Name = " - VM Žymos (Tags)"; Text = $tagText; Color = $tagColor }
}

# --- 4. IŠVEDIMAS ---
$date = Get-Date -Format "yyyy-MM-dd HH:mm"

Write-Host "`n--- GALUTINIS REZULTATAS (Padarykite nuotrauką) ---" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Gray
Write-Host "$($Setup.HeaderTitle)"
Write-Host "$($LocCfg.LabName)" -ForegroundColor Yellow
Write-Host "Data: $date"
Write-Host "Studentas: $CurrentIdentity"
Write-Host "==================================================" -ForegroundColor Gray

foreach ($res in $resourceResults) {
    if ($res.Name -match "^ -") {
        # Įtrauka sub-elementams
        $label = "   $($res.Name.Replace(' - ', '')):"
    } else {
        $label = "$($res.Name):"
    }
    
    $targetWidth = 30
    $neededSpaces = $targetWidth - $label.Length
    if ($neededSpaces -lt 1) { $neededSpaces = 1 }
    $padding = " " * $neededSpaces
    
    Write-Host "$label$padding" -NoNewline
    Write-Host $res.Text -ForegroundColor $res.Color
}

Write-Host "==================================================" -ForegroundColor Gray
if (-not $lb) {
    Write-Host "Patarimas: Jei nerandate Load Balancer, patikrinkite 'az network lb create' komandą." -ForegroundColor DarkGray
}
Write-Host ""