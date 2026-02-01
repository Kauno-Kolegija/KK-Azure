# --- VERSIJOS KONTROLĖ ---
$ScriptVersion = "LAB 04: Defense in Depth (Platinum - Full Topology)"
Clear-Host
Write-Host "--------------------------------------------------"
Write-Host $ScriptVersion -ForegroundColor Magenta
Write-Host "Vykdoma pilna topologijos ir saugumo patikra..."
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
    $rgText = "[DĖMESIO] - Rasta tik $($labRGs.Count) grupės (Reikia 3)"
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

# --- GAVIMAS VISŲ VM ---
$allVMs = Get-AzVM

# C. Admin Serveris (Klientas) - NAUJA DALIS
$vmAdmin = $allVMs | Where-Object Name -match "VM-Admin|Admin-VM" | Select-Object -First 1

if ($vmAdmin) {
    # Tikriname, ar jis tikrai VNet-Admin tinkle
    $nicId = $vmAdmin.NetworkProfile.NetworkInterfaces[0].Id
    $nic = Get-AzNetworkInterface -ResourceId $nicId
    $subnetId = $nic.IpConfigurations[0].Subnet.Id
    
    if ($subnetId -match "VNet-Admin") {
        $adminText = "[OK] - Rastas ir prijungtas prie VNet-Admin"
        $adminColor = "Green"
    } else {
        $adminText = "[DĖMESIO] - VM yra, bet ne 'VNet-Admin' tinkle"
        $adminColor = "Yellow"
    }
} else {
    $adminText = "[TRŪKSTA] - Nerastas serveris VM-Admin"
    $adminColor = "Red"
}
$resourceResults += [PSCustomObject]@{ Name = "Admin Serveris"; Text = $adminText; Color = $adminColor }

# D. Sandėlio Serveris (Taikinys)
$vmSandelys = $allVMs | Where-Object Name -match "VM-Sandelis|Sand-VM|Sandelis-VM" | Select-Object -First 1

if ($vmSandelys) {
    $nicId = $vmSandelys.NetworkProfile.NetworkInterfaces[0].Id
    $nic = Get-AzNetworkInterface -ResourceId $nicId
    
    # 1. Tikriname ASG
    if ($nic.IpConfigurations.ApplicationSecurityGroups.Id -match "ASG-DB-Servers") {
        $asgText = "[OK] - Priskirta grupė 'ASG-DB-Servers'"
        $asgColor = "Green"
    } else {
        $asgText = "[TRŪKSTA] - VM neturi ASG grupės"
        $asgColor = "Red"
    }
    $resourceResults += [PSCustomObject]@{ Name = "Sandėlio VM (ASG)"; Text = $asgText; Color = $asgColor }

    # 2. Tikriname VM NSG (Deny)
    if ($nic.NetworkSecurityGroup) {
        $nsgIdParts = $nic.NetworkSecurityGroup.Id -split '/'
        $vmNsg = Get-AzNetworkSecurityGroup -ResourceGroupName $nsgIdParts[4] -Name $nsgIdParts[-1]
        
        $denyRule = $vmNsg.SecurityRules | Where-Object { 
            ($_.Access -eq "Deny") -and 
            (($_.DestinationPortRange -contains "1433") -or ($_.DestinationPortRange -contains "80")) 
        }
        
        if ($denyRule) {
            if ($denyRule.Priority -le 1000) {
                $vmSecText = "[OK] - DENY taisyklė (Port $($denyRule.DestinationPortRange), Prio: $($denyRule.Priority))"
                $vmSecColor = "Green"
            } else {
                $vmSecText = "[ĮSPĖJIMAS] - DENY prioritetas per žemas!"
                $vmSecColor = "Yellow"
            }
        } else {
            $vmSecText = "[KLAIDA] - Nerasta DENY taisyklė (1433/80)"
            $vmSecColor = "Red"
        }
    } else {
        $vmSecText = "[TRŪKSTA] - Serveriui nepriskirta NSG"
        $vmSecColor = "Red"
    }
    $resourceResults += [PSCustomObject]@{ Name = "Saugumas (VM Siena)"; Text = $vmSecText; Color = $vmSecColor }

} else {
    $resourceResults += [PSCustomObject]@{ Name = "Sandėlio VM"; Text = "[TRŪKSTA] - Serveris nerastas"; Color = "Red" }
}

# E. Saugumas: Tinklo Siena (Subnet NSG)
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