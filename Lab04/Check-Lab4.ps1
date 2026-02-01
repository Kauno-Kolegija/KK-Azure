# --- VERSIJOS KONTROLĖ ---
$ScriptVersion = "LAB 04/05 TIKRINIMAS: Defense in Depth (Universalus v3)"
Clear-Host
Write-Host "--------------------------------------------------"
Write-Host $ScriptVersion -ForegroundColor Magenta
Write-Host "Vykdoma patikra (RG-LAB04/05 ir Port 1433/80)..."
Write-Host "--------------------------------------------------"

# --- 1. UŽKRAUNAME BENDRAS FUNKCIJAS ---
try {
    irm "https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/configs/common.ps1" | iex
} catch {
    Write-Error "Nepavyko užkrauti bazinių funkcijų. Patikrinkite interneto ryšį."
    exit
}

# --- 2. INICIJUOJAME DARBĄ ---
# Nurodome nuorodą į CONFIG failą (Įsitikinkite, kad šis failas egzistuoja GitHub)
$ConfigUrl = "https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/Lab04/Check-Lab4-config.json"
try {
    $Setup = Initialize-Lab -LocalConfigUrl $ConfigUrl
    $LocCfg = $Setup.LocalConfig
} catch {
    Write-Warning "Nepavyko užkrauti Config failo. Naudojami numatytieji nustatymai."
    $LocCfg = @{ LabName = "Defense in Depth Lab" }
}

# Nustatome vartotoją
$CurrentIdentity = az ad signed-in-user show --query userPrincipalName -o tsv
if (-not $CurrentIdentity) { $CurrentIdentity = "Studentas" }

# --- 3. DUOMENŲ RINKIMAS ---
$resourceResults = @()

# A. Resursų Grupės (Universalus tikrinimas: LAB04 arba LAB05)
$labRGs = Get-AzResourceGroup | Where-Object { $_.ResourceGroupName -match "RG-LAB0[45]" }

if ($labRGs.Count -ge 3) {
    $rgText = "[OK] - Rastos 3+ grupės (Admin, Infra, Sandėlys)"
    $rgColor = "Green"
} else {
    $rgText = "[DĖMESIO] - Rasta tik $($labRGs.Count) grupės (Reikėjo 3, pvz. RG-LAB05-...)"
    $rgColor = "Yellow"
}
$resourceResults += [PSCustomObject]@{ Name = "Resursų grupės"; Text = $rgText; Color = $rgColor }

# B. Tinklai ir Peering
$allVnets = Get-AzVirtualNetwork
$vnetAdmin = $allVnets | Where-Object Name -match "VNet-Admin" | Select-Object -First 1
$vnetSandelys = $allVnets | Where-Object Name -match "VNet-Sandelys|VNet-Sandelis" | Select-Object -First 1

if ($vnetAdmin -and $vnetSandelys) {
    # Peering tikrinimas
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

# C. Serveris ir ASG
$allVMs = Get-AzVM
# Ieškome lanksčiai: VM-Sandelis, Sand-VM, Sandelis-VM
$vmSandelys = $allVMs | Where-Object Name -match "VM-Sandelis|Sand-VM|Sandelis-VM" | Select-Object -First 1

if ($vmSandelys) {
    $nicId = $vmSandelys.NetworkProfile.NetworkInterfaces[0].Id
    $nic = Get-AzNetworkInterface -ResourceId $nicId
    
    # Tikriname ASG (Grupavimą)
    if ($nic.IpConfigurations.ApplicationSecurityGroups.Id -match "ASG-DB-Servers") {
        $asgText = "[OK] - Serveris priskirtas grupei 'ASG-DB-Servers'"
        $asgColor = "Green"
    } else {
        $asgText = "[TRŪKSTA] - VM neturi priskirtos ASG grupės"
        $asgColor = "Red"
    }
    $resourceResults += [PSCustomObject]@{ Name = "Serverio grupavimas (ASG)"; Text = $asgText; Color = $asgColor }

    # D. Saugumas 1: Serverio Siena (VM NSG - Deny)
    # Tikriname, ar yra Deny taisyklė ant 1433 ARBA 80 porto
    if ($nic.NetworkSecurityGroup) {
        $vmNsg = Get-AzNetworkSecurityGroup -ResourceId $nic.NetworkSecurityGroup.Id
        $denyRule = $vmNsg.SecurityRules | Where-Object { 
            ($_.Access -eq "Deny") -and 
            (($_.DestinationPortRange -contains "1433") -or ($_.DestinationPortRange -contains "80")) 
        }
        
        if ($denyRule) {
            $vmSecText = "[OK] - Rasta DENY taisyklė (Port $($denyRule.DestinationPortRange))"
            $vmSecColor = "Green"
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
    # Randame bet kurį potinklį, kuris turi NSG
    $subnet = $vnetSandelys.Subnets | Where-Object { $_.NetworkSecurityGroup -ne $null } | Select-Object -First 1
    
    if ($subnet) {
        $subNsg = Get-AzNetworkSecurityGroup -ResourceId $subnet.NetworkSecurityGroup.Id
        # Tikriname, ar yra Allow taisyklė ant 1433 ARBA 80 porto
        $allowRule = $subNsg.SecurityRules | Where-Object { 
            ($_.Access -eq "Allow") -and 
            (($_.DestinationPortRange -contains "1433") -or ($_.DestinationPortRange -contains "80")) 
        }
        
        if ($allowRule) {
            $netSecText = "[OK] - Subnet NSG leidžia Port $($allowRule.DestinationPortRange)"
            $netSecColor = "Green"
        } else {
            $netSecText = "[KLAIDA] - Subnet NSG neturi Allow taisyklės (1433/80)"
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

Write-Host "`n--- GALUTINIS REZULTATAS (Padarykite nuotrauką) ---" -ForegroundColor Cyan
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