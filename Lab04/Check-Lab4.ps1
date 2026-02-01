# --- VERSIJOS KONTROLĖ ---
$ScriptVersion = "LAB 4 TIKRINIMAS: Defense in Depth"
Clear-Host
Write-Host "--------------------------------------------------"
Write-Host $ScriptVersion -ForegroundColor Magenta
Write-Host "Vykdoma paskirstytų resursų ir saugumo patikra..."
Write-Host "--------------------------------------------------"

# --- 1. UŽKRAUNAME BENDRAS FUNKCIJAS ---
try {
    irm "https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/configs/common.ps1" | iex
} catch {
    Write-Error "Nepavyko užkrauti bazinių funkcijų."
    exit
}

# --- 2. INICIJUOJAME DARBĄ ---
# Nurodome vietinį config failą (arba URL ateityje)
$Setup = Initialize-Lab -LocalConfigUrl "Check-Lab4-config.json"
$LocCfg = $Setup.LocalConfig
$CurrentIdentity = az ad signed-in-user show --query userPrincipalName -o tsv
if (-not $CurrentIdentity) { $CurrentIdentity = "Studentas" }

# --- 3. DUOMENŲ RINKIMAS ---
$resourceResults = @()

# A. Resursų Grupės (Tikriname ar yra 3)
$labRGs = Get-AzResourceGroup | Where-Object { $_.ResourceGroupName -match "RG-LAB04" }
if ($labRGs.Count -ge 3) {
    $rgText = "[OK] - Rastos 3+ grupės (Infra, Admin, Sandėlys)"
    $rgColor = "Green"
} else {
    $rgText = "[DĖMESIO] - Rasta tik $($labRGs.Count) grupės (Reikėjo paskirstyti į 3)"
    $rgColor = "Yellow"
}
$resourceResults += [PSCustomObject]@{ Name = "Resursų grupės"; Text = $rgText; Color = $rgColor }

# B. Tinklai ir Peering
$allVnets = Get-AzVirtualNetwork
$vnetAdmin = $allVnets | Where-Object Name -match "VNet-Admin" | Select-Object -First 1
$vnetSandelys = $allVnets | Where-Object Name -match "VNet-Sandelys" | Select-Object -First 1

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

# C. Serveriai ir ASG (Grupavimas)
$allVMs = Get-AzVM
$vmSandelys = $allVMs | Where-Object Name -match "VM-Sandelis|Sand-VM" | Select-Object -First 1

if ($vmSandelys) {
    # Tikriname ar VM turi ASG
    $nicId = $vmSandelys.NetworkProfile.NetworkInterfaces[0].Id
    $nic = Get-AzNetworkInterface -ResourceId $nicId
    
    if ($nic.IpConfigurations.ApplicationSecurityGroups.Id -match "ASG-DB-Servers") {
        $asgText = "[OK] - Priskirta grupė 'ASG-DB-Servers'"
        $asgColor = "Green"
    } else {
        $asgText = "[TRŪKSTA] - VM neturi ASG grupės"
        $asgColor = "Red"
    }
    $resourceResults += [PSCustomObject]@{ Name = "Serverio grupavimas"; Text = $asgText; Color = $asgColor }

    # D. Saugumas 1: Serverio Siena (VM NSG - Deny)
    # Ieškome NSG, kuri priskirta tiesiai NIC plokštei
    if ($nic.NetworkSecurityGroup) {
        $vmNsg = Get-AzNetworkSecurityGroup -ResourceId $nic.NetworkSecurityGroup.Id
        $denyRule = $vmNsg.SecurityRules | Where-Object { ($_.Access -eq "Deny") -and ($_.DestinationPortRange -contains "1433") }
        
        if ($denyRule) {
            $vmSecText = "[OK] - Rasta DENY taisyklė (Port 1433)"
            $vmSecColor = "Green"
        } else {
            $vmSecText = "[KLAIDA] - Nerasta taisyklė, blokuojanti 1433"
            $vmSecColor = "Red"
        }
    } else {
        $vmSecText = "[TRŪKSTA] - Serveris neturi asmeninės NSG"
        $vmSecColor = "Red"
    }
    $resourceResults += [PSCustomObject]@{ Name = "Saugumas (VM lygyje)"; Text = $vmSecText; Color = $vmSecColor }

} else {
    $resourceResults += [PSCustomObject]@{ Name = "VM-Sandelis"; Text = "[TRŪKSTA] - Serveris nerastas"; Color = "Red" }
}

# E. Saugumas 2: Tinklo Siena (Subnet NSG - Allow)
if ($vnetSandelys) {
    # Ieškome potinklio (dažniausiai 'default' arba 'VNet-Sandelis-Servers')
    $subnet = $vnetSandelys.Subnets | Where-Object { $_.NetworkSecurityGroup -ne $null } | Select-Object -First 1
    
    if ($subnet) {
        # Tikriname ar NSG turi Allow taisyklę
        $subNsg = Get-AzNetworkSecurityGroup -ResourceId $subnet.NetworkSecurityGroup.Id
        $allowRule = $subNsg.SecurityRules | Where-Object { ($_.Access -eq "Allow") -and ($_.DestinationPortRange -contains "1433") }
        
        if ($allowRule) {
            $netSecText = "[OK] - Subnet NSG leidžia Port 1433"
            $netSecColor = "Green"
        } else {
            $netSecText = "[KLAIDA] - Subnet NSG neturi Allow 1433 taisyklės"
            $netSecColor = "Red"
        }
    } else {
        $netSecText = "[TRŪKSTA] - Potinkliui nepriskirta jokia NSG"
        $netSecColor = "Red"
    }
    $resourceResults += [PSCustomObject]@{ Name = "Saugumas (Tinklo lygyje)"; Text = $netSecText; Color = $netSecColor }
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
    $label = "$($res.Name):"
    $targetWidth = 30
    $neededSpaces = $targetWidth - $label.Length
    if ($neededSpaces -lt 1) { $neededSpaces = 1 }
    $padding = " " * $neededSpaces
    
    Write-Host "$label$padding" -NoNewline
    Write-Host $res.Text -ForegroundColor $res.Color
}

Write-Host "==================================================" -ForegroundColor Gray
Write-Host ""