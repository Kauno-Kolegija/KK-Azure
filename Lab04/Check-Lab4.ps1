# --- VERSIJOS KONTROLĖ ---
$ScriptVersion = "LAB 4: Defense in Depth (Gold Edition)"
Clear-Host
Write-Host "--------------------------------------------------"
Write-Host $ScriptVersion -ForegroundColor Magenta
Write-Host "Vykdoma išplėstinė patikra (Priority + Region check)..."
Write-Host "--------------------------------------------------"

# --- 1. UŽKRAUNAME BENDRAS FUNKCIJAS ---
try {
    irm "https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/configs/common.ps1" | iex
} catch {
    Write-Error "Nepavyko užkrauti bazinių funkcijų."
    exit
}

# --- 2. INICIJUOJAME DARBĄ ---
$ConfigUrl = "https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/Lab04/Check-Lab4-config.json"
try {
    $Setup = Initialize-Lab -LocalConfigUrl $ConfigUrl
    $LocCfg = $Setup.LocalConfig
} catch {
    $LocCfg = @{ LabName = "Defense in Depth Lab" }
}

$CurrentIdentity = az ad signed-in-user show --query userPrincipalName -o tsv
if (-not $CurrentIdentity) { $CurrentIdentity = "Studentas" }

# --- 3. DUOMENŲ RINKIMAS ---
$resourceResults = @()

# A. Resursų Grupės
$labRGs = Get-AzResourceGroup | Where-Object { $_.ResourceGroupName -match "RG-LAB0[45]" }
if ($labRGs.Count -ge 3) {
    $rgText = "[OK] - Rastos 3+ grupės"
    $rgColor = "Green"
} else {
    $rgText = "[DĖMESIO] - Rasta tik $($labRGs.Count) grupės"
    $rgColor = "Yellow"
}
$resourceResults += [PSCustomObject]@{ Name = "Resursų grupės"; Text = $rgText; Color = $rgColor }

# B. Tinklai ir Peering
$allVnets = Get-AzVirtualNetwork
$vnetAdmin = $allVnets | Where-Object Name -match "VNet-Admin" | Select-Object -First 1
$vnetSandelys = $allVnets | Where-Object Name -match "VNet-Sandelys|VNet-Sandelis" | Select-Object -First 1

if ($vnetAdmin -and $vnetSandelys) {
    $peering = $vnetAdmin.VirtualNetworkPeerings | Select-Object -First 1
    if ($peering -and $peering.PeeringState -eq "Connected") {
        $peerText = "[OK] - Connected (Sujungta)"
        $peerColor = "Green"
    } else {
        $peerText = "[KLAIDA] - Peering nerastas arba atsijungęs"
        $peerColor = "Red"
    }
    $resourceResults += [PSCustomObject]@{ Name = "Tinklų sujungimas"; Text = $peerText; Color = $peerColor }
} else {
    $resourceResults += [PSCustomObject]@{ Name = "Tinklai"; Text = "[TRŪKSTA] - Nerasti VNet tinklai"; Color = "Red" }
}

# C. Serveris, Regionas ir ASG
$allVMs = Get-AzVM
$vmSandelys = $allVMs | Where-Object Name -match "VM-Sandelis|Sand-VM|Sandelis-VM" | Select-Object -First 1

if ($vmSandelys) {
    $nicId = $vmSandelys.NetworkProfile.NetworkInterfaces[0].Id
    $nic = Get-AzNetworkInterface -ResourceId $nicId
    
    # Tikriname ASG ir Regioną
    if ($nic.IpConfigurations.ApplicationSecurityGroups.Id -match "ASG-DB-Servers") {
        # Papildomas tikrinimas: Regionas
        $asgId = $nic.IpConfigurations.ApplicationSecurityGroups[0].Id
        # (Čia supaprastinta, nes ASG objektą gauti lėčiau, bet jei priskirta - vadinasi regionas geras)
        $asgText = "[OK] - Serveris priskirtas grupei 'ASG-DB-Servers'"
        $asgColor = "Green"
    } else {
        $asgText = "[TRŪKSTA] - VM neturi priskirtos ASG grupės"
        $asgColor = "Red"
    }
    $resourceResults += [PSCustomObject]@{ Name = "Serverio grupavimas (ASG)"; Text = $asgText; Color = $asgColor }

    # D. Saugumas 1: Serverio Siena (VM NSG - Deny)
    if ($nic.NetworkSecurityGroup) {
        $nsgIdParts = $nic.NetworkSecurityGroup.Id -split '/'
        $vmNsg = Get-AzNetworkSecurityGroup -ResourceGroupName $nsgIdParts[4] -Name $nsgIdParts[-1]
        
        $denyRule = $vmNsg.SecurityRules | Where-Object { 
            ($_.Access -eq "Deny") -and 
            (($_.DestinationPortRange -contains "1433") -or ($_.DestinationPortRange -contains "80")) 
        }
        
        if ($denyRule) {
            # Tikriname prioritetą
            if ($denyRule.Priority -le 1000) {
                $vmSecText = "[OK] - DENY taisyklė (Port $($denyRule.DestinationPortRange), Prio: $($denyRule.Priority))"
                $vmSecColor = "Green"
            } else {
                $vmSecText = "[ĮSPĖJIMAS] - DENY prioritetas ($($denyRule.Priority)) per žemas!"
                $vmSecColor = "Yellow"
            }
        } else {
            $vmSecText = "[KLAIDA] - Nerasta taisyklė, blokuojanti 1433 arba 80"
            $vmSecColor = "Red"
        }
    } else {
        $vmSecText = "[TRŪKSTA] - Serveriui nepriskirta asmeninė NSG"
        $vmSecColor = "Red"
    }
    $resourceResults += [PSCustomObject]@{ Name = "Saugumas (VM Siena)"; Text = $vmSecText; Color = $vmSecColor }

} else {
    $resourceResults += [PSCustomObject]@{ Name = "VM-Sandelis"; Text = "[TRŪKSTA] - Serveris nerastas"; Color = "Red" }
}

# E. Saugumas 2: Tinklo Siena (Subnet NSG - Allow)
if ($vnetSandelys) {
    $subnet = $vnetSandelys.Subnets | Where-Object { $_.NetworkSecurityGroup -ne $null } | Select-Object -First 1
    
    if ($subnet) {
        $nsgIdParts = $subnet.NetworkSecurityGroup.Id -split '/'
        $subNsg = Get-AzNetworkSecurityGroup -ResourceGroupName $nsgIdParts[4] -Name $nsgIdParts[-1]
        
        $allowRule = $subNsg.SecurityRules | Where-Object { 
            ($_.Access -eq "Allow") -and 
            (($_.DestinationPortRange -contains "1433") -or ($_.DestinationPortRange -contains "80")) 
        }
        
        if ($allowRule) {
            $netSecText = "[OK] - Subnet NSG leidžia Port $($allowRule.DestinationPortRange)"
            $netSecColor = "Green"
        } else {
            $netSecText = "[KLAIDA] - Subnet NSG neturi Allow taisyklės"
            $netSecColor = "Red"
        }
    } else {
        $netSecText = "[TRŪKSTA] - Potinkliui nepriskirta jokia NSG"
        $netSecColor = "Red"
    }
    $resourceResults += [PSCustomObject]@{ Name = "Saugumas (Tinklo Siena)"; Text = $netSecText; Color = $netSecColor }
}

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