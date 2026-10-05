# ============================================================
# LAB 4 - Azure Networking validation
# ============================================================

# --- 1. KALBA ---
if ($Lang -notin @("LT", "EN")) { $Lang = "LT" }

# --- 2. UŽKRAUNAME BENDRAS FUNKCIJAS ---
try {
    if ($PSScriptRoot) {
        . (Join-Path $PSScriptRoot '../configs/common.ps1')
    }
    else {
        Invoke-RestMethod 'https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/configs/common.ps1' -ErrorAction Stop | Invoke-Expression
    }
}
catch {
    Write-Error "Failed to load common functions."
    throw
}

# --- 3. INICIJUOJAME DARBĄ ---
$Setup = Initialize-Lab `
    -LocalConfigUrl "https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/Lab04/Check-Lab4-config.json" `
    -Lang $Lang

$LocCfg  = $Setup.LocalConfig
$Msg     = $Setup.Messages
$LabName = $LocCfg.LabName

$OkStatus      = $Msg.Ok
$ErrorStatus   = $Msg.Error
$MissingStatus = "TRŪKSTA"

$resourceResults = @()

# ============================================================
# PAGALBINĖS FUNKCIJOS
# ============================================================

function Add-Result {
    param (
        [string]$Name,
        [string]$Text,
        [string]$Color = "Green"
    )

    $script:resourceResults += [PSCustomObject]@{
        Name  = $Name
        Text  = $Text
        Color = $Color
    }
}

function Get-NicFromVM {
    param ($VM)

    if (-not $VM -or -not $VM.NetworkProfile.NetworkInterfaces[0].Id) {
        return $null
    }

    $nicId = $VM.NetworkProfile.NetworkInterfaces[0].Id
    $parts = $nicId -split '/'

    if ($parts.Count -lt 9) {
        return $null
    }

    Get-AzNetworkInterface `
        -ResourceGroupName $parts[4] `
        -Name $parts[-1] `
        -ErrorAction SilentlyContinue
}

function Test-PortRule {
    param (
        $Rule,
        [string]$Port
    )

    if (-not $Rule) { return $false }

    $ports = @()

    if ($Rule.DestinationPortRange) {
        $ports += @($Rule.DestinationPortRange)
    }

    if ($Rule.DestinationPortRanges) {
        $ports += @($Rule.DestinationPortRanges)
    }

    return ($ports -contains $Port)
}

# ============================================================
# A. RESOURCE GROUPS
# ============================================================

$allRGs = @(Get-AzResourceGroup)

$rgInfra = $allRGs |
    Where-Object ResourceGroupName -Match $LocCfg.ResourceGroups.Infrastructure |
    Select-Object -First 1

$rgAdmin = $allRGs |
    Where-Object ResourceGroupName -Match $LocCfg.ResourceGroups.Administration |
    Select-Object -First 1

$rgWarehouse = $allRGs |
    Where-Object ResourceGroupName -Match $LocCfg.ResourceGroups.Warehouse |
    Select-Object -First 1

$foundRGs = @($rgInfra, $rgAdmin, $rgWarehouse | Where-Object { $_ }).Count

if ($rgInfra -and $rgAdmin -and $rgWarehouse) {
    Add-Result "Resursų grupės" "[$OkStatus] - 3/3" "Green"
}
else {
    Add-Result "Resursų grupės" "[$ErrorStatus] - Rasta $foundRGs/3" "Red"
}

# ============================================================
# B. VNET-ADMIN
# ============================================================

$allVNets = @(Get-AzVirtualNetwork)

$vnetAdmin = $allVNets |
    Where-Object Name -EQ $LocCfg.Networks.Admin.Name |
    Select-Object -First 1

if ($vnetAdmin) {
    $adminAddressOk = $vnetAdmin.AddressSpace.AddressPrefixes -contains $LocCfg.Networks.Admin.AddressSpace

    $frontEnd = $vnetAdmin.Subnets |
        Where-Object Name -EQ $LocCfg.Networks.Admin.Subnets.FrontEnd.Name |
        Select-Object -First 1

    $backEnd = $vnetAdmin.Subnets |
        Where-Object Name -EQ $LocCfg.Networks.Admin.Subnets.BackEnd.Name |
        Select-Object -First 1

    if (-not $adminAddressOk) {
        $actual = $vnetAdmin.AddressSpace.AddressPrefixes -join ", "
        Add-Result "VNet-Admin" "[$ErrorStatus] - Adresacija: $actual" "Red"
    }
    else {
        $details = @()
        $hasWarning = $false

        if ($frontEnd -and $frontEnd.AddressPrefix -eq $LocCfg.Networks.Admin.Subnets.FrontEnd.Prefix) {
            $details += "FE $($frontEnd.AddressPrefix)"
        }
        else {
            $details += "FE neteisingas"
            $hasWarning = $true
        }

        if ($backEnd -and $backEnd.AddressPrefix -eq $LocCfg.Networks.Admin.Subnets.BackEnd.Prefix) {
            $details += "BE $($backEnd.AddressPrefix)"
        }
        else {
            $details += "BE neteisingas"
            $hasWarning = $true
        }

        if ($hasWarning) {
            Add-Result "VNet-Admin" "[$WarningStatus] - $($LocCfg.Networks.Admin.AddressSpace); $($details -join '; ')" "Yellow"
        }
        else {
            Add-Result "VNet-Admin" "[$OkStatus] - $($LocCfg.Networks.Admin.AddressSpace); $($details -join '; ')" "Green"
        }
    }
}
else {
    Add-Result "VNet-Admin" "[$MissingStatus] - Tinklas nerastas" "Red"
}

# ============================================================
# C. VNET-SANDELIS
# ============================================================

$vnetWarehouse = $allVNets |
    Where-Object Name -EQ $LocCfg.Networks.Warehouse.Name |
    Select-Object -First 1

if ($vnetWarehouse) {
    $warehouseAddressOk = $vnetWarehouse.AddressSpace.AddressPrefixes -contains $LocCfg.Networks.Warehouse.AddressSpace

    $serverSubnet = $vnetWarehouse.Subnets |
        Where-Object Name -EQ $LocCfg.Networks.Warehouse.Subnets.Servers.Name |
        Select-Object -First 1

    if (-not $warehouseAddressOk) {
        $actual = $vnetWarehouse.AddressSpace.AddressPrefixes -join ", "
        Add-Result "VNet-Sandelis" "[$ErrorStatus] - Adresacija: $actual" "Red"
    }
    else {
        if ($serverSubnet -and $serverSubnet.AddressPrefix -eq $LocCfg.Networks.Warehouse.Subnets.Servers.Prefix) {
            Add-Result "VNet-Sandelis" "[$OkStatus] - $($LocCfg.Networks.Warehouse.AddressSpace); Servers $($serverSubnet.AddressPrefix)" "Green"
        }
        else {
            Add-Result "VNet-Sandelis" "[$WarningStatus] - $($LocCfg.Networks.Warehouse.AddressSpace); Servers neteisingas" "Yellow"
        }
    }
}
else {
    Add-Result "VNet-Sandelis" "[$MissingStatus] - Tinklas nerastas" "Red"
}

# ============================================================
# D. VIRTUAL MACHINES
# ============================================================

$allVMs = @(Get-AzVM)

$vmAdmin = $allVMs |
    Where-Object Name -EQ $LocCfg.VirtualMachines.Admin |
    Select-Object -First 1

$vmWarehouse = $allVMs |
    Where-Object Name -EQ $LocCfg.VirtualMachines.Warehouse |
    Select-Object -First 1

$nicAdmin = Get-NicFromVM $vmAdmin
$nicWarehouse = Get-NicFromVM $vmWarehouse

if ($vmAdmin -and $nicAdmin) {
    $adminIp = $nicAdmin.IpConfigurations[0].PrivateIpAddress
    $adminSubnetId = $nicAdmin.IpConfigurations[0].Subnet.Id

    $correctRG = $vmAdmin.ResourceGroupName -match $LocCfg.ResourceGroups.Administration
    $correctSubnet = $adminSubnetId -match "/virtualNetworks/VNet-Admin/subnets/VNet-Admin-FrontEnd$"

    if ($correctRG -and $correctSubnet) {
        Add-Result "VM-Admin" "[$OkStatus] - $adminIp" "Green"
    }
    else {
        Add-Result "VM-Admin" "[$ErrorStatus] - Netinkama RG arba potinklis ($adminIp)" "Red"
    }
}
else {
    Add-Result "VM-Admin" "[$MissingStatus] - Serveris nerastas" "Red"
}

if ($vmWarehouse -and $nicWarehouse) {
    $warehouseIp = $nicWarehouse.IpConfigurations[0].PrivateIpAddress
    $warehouseSubnetId = $nicWarehouse.IpConfigurations[0].Subnet.Id

    $correctRG = $vmWarehouse.ResourceGroupName -match $LocCfg.ResourceGroups.Warehouse
    $correctSubnet = $warehouseSubnetId -match "/virtualNetworks/VNet-Sandelis/subnets/VNet-Sandelis-Servers$"

    if ($correctRG -and $correctSubnet) {
        Add-Result "VM-Sandelis" "[$OkStatus] - $warehouseIp" "Green"
    }
    else {
        Add-Result "VM-Sandelis" "[$ErrorStatus] - Netinkama RG arba potinklis ($warehouseIp)" "Red"
    }
}
else {
    Add-Result "VM-Sandelis" "[$MissingStatus] - Serveris nerastas" "Red"
}

# ============================================================
# E. VNET PEERING
# ============================================================

if ($vnetAdmin -and $vnetWarehouse) {
    $adminToWarehouse = $vnetAdmin.VirtualNetworkPeerings |
        Where-Object {
            $_.RemoteVirtualNetwork.Id -eq $vnetWarehouse.Id -and
            $_.PeeringState -eq "Connected"
        } |
        Select-Object -First 1

    $warehouseToAdmin = $vnetWarehouse.VirtualNetworkPeerings |
        Where-Object {
            $_.RemoteVirtualNetwork.Id -eq $vnetAdmin.Id -and
            $_.PeeringState -eq "Connected"
        } |
        Select-Object -First 1

    if ($adminToWarehouse -and $warehouseToAdmin) {
        Add-Result "VNet Peering" "[$OkStatus] - Connected" "Green"
    }
    else {
        Add-Result "VNet Peering" "[$ErrorStatus] - Peering nesujungtas abiem kryptimis" "Red"
    }
}
else {
    Add-Result "VNet Peering" "[$MissingStatus] - Trūksta VNet" "Red"
}

# ============================================================
# F. APPLICATION SECURITY GROUP
# ============================================================

$asg = Get-AzApplicationSecurityGroup -ErrorAction SilentlyContinue |
    Where-Object Name -EQ $LocCfg.ApplicationSecurityGroup |
    Select-Object -First 1

if ($asg -and $nicWarehouse) {
    $asgIds = @($nicWarehouse.IpConfigurations.ApplicationSecurityGroups.Id)

    if ($asgIds -contains $asg.Id) {
        Add-Result "ASG-DB-Servers" "[$OkStatus] - VM-Sandelis priskirtas" "Green"
    }
    else {
        Add-Result "ASG-DB-Servers" "[$ErrorStatus] - VM-Sandelis nepriskirtas" "Red"
    }
}
elseif ($asg) {
    Add-Result "ASG-DB-Servers" "[$ErrorStatus] - ASG yra, VM nerasta" "Red"
}
else {
    Add-Result "ASG-DB-Servers" "[$MissingStatus] - ASG nerasta" "Red"
}

# ============================================================
# G. SUBNET NSG
# ============================================================

$subnetNsg = Get-AzNetworkSecurityGroup -ErrorAction SilentlyContinue |
    Where-Object Name -EQ $LocCfg.SubnetNSG.Name |
    Select-Object -First 1

$subnetNsgAssociated = $false

if ($serverSubnet -and $serverSubnet.NetworkSecurityGroup -and $subnetNsg) {
    $subnetNsgAssociated = $serverSubnet.NetworkSecurityGroup.Id -eq $subnetNsg.Id
}

if (-not $subnetNsg) {
    Add-Result "Subnet NSG" "[$MissingStatus] - $($LocCfg.SubnetNSG.Name)" "Red"
}
elseif (-not $subnetNsgAssociated) {
    Add-Result "Subnet NSG" "[$ErrorStatus] - NSG nepriskirta VNet-Sandelis-Servers" "Red"
}
else {
    $sqlRule = $subnetNsg.SecurityRules |
        Where-Object Name -EQ $LocCfg.SubnetNSG.SqlRule.Name |
        Select-Object -First 1

    $sqlPortOk = Test-PortRule $sqlRule $LocCfg.SubnetNSG.SqlRule.Port

    $sqlAsgOk = $false

    if ($sqlRule -and $asg) {
        $sqlAsgIds = @($sqlRule.DestinationApplicationSecurityGroups.Id)
        $sqlAsgOk = $sqlAsgIds -contains $asg.Id
    }

    $sqlOk =
        $sqlRule -and
        $sqlRule.Access -eq $LocCfg.SubnetNSG.SqlRule.Access -and
        $sqlRule.Priority -eq $LocCfg.SubnetNSG.SqlRule.Priority -and
        $sqlPortOk -and
        $sqlAsgOk

    $pingRule = $subnetNsg.SecurityRules |
        Where-Object Name -EQ $LocCfg.SubnetNSG.PingRule.Name |
        Select-Object -First 1

    $pingProtocolOk =
        $pingRule.Protocol -in @("Icmp", "IcmpV4")

    $pingAsgOk = $false

    if ($pingRule -and $asg) {
        $pingAsgIds = @($pingRule.DestinationApplicationSecurityGroups.Id)
        $pingAsgOk = $pingAsgIds -contains $asg.Id
    }

    $pingOk =
        $pingRule -and
        $pingRule.Access -eq $LocCfg.SubnetNSG.PingRule.Access -and
        $pingRule.Priority -eq $LocCfg.SubnetNSG.PingRule.Priority -and
        $pingProtocolOk -and
        $pingAsgOk

    if ($sqlOk -and $pingOk) {
        Add-Result "Subnet NSG" "[$OkStatus] - Allow-SQL, Allow-Ping" "Green"
    }
    else {
        $problems = @()

        if (-not $sqlOk) { $problems += "Allow-SQL" }
        if (-not $pingOk) { $problems += "Allow-Ping" }

        Add-Result "Subnet NSG" "[$ErrorStatus] - Patikrinkite: $($problems -join ', ')" "Red"
    }
}

# ============================================================
# H. VM NIC NSG
# ============================================================

if ($nicWarehouse -and $nicWarehouse.NetworkSecurityGroup) {
    $vmNsgId = $nicWarehouse.NetworkSecurityGroup.Id
    $parts = $vmNsgId -split '/'

    $vmNsg = Get-AzNetworkSecurityGroup `
        -ResourceGroupName $parts[4] `
        -Name $parts[-1] `
        -ErrorAction SilentlyContinue

    $denyRule = $vmNsg.SecurityRules |
        Where-Object Name -EQ $LocCfg.VmNSG.Rule.Name |
        Select-Object -First 1

    $denyPortOk = Test-PortRule $denyRule $LocCfg.VmNSG.Rule.Port

    $denyOk =
        $denyRule -and
        $denyRule.Access -eq $LocCfg.VmNSG.Rule.Access -and
        $denyRule.Priority -eq $LocCfg.VmNSG.Rule.Priority -and
        $denyPortOk

    if ($denyOk) {
        Add-Result "VM NSG" "[$OkStatus] - Deny-SQL-LocalServer (1433, Priority 400)" "Green"
    }
    else {
        Add-Result "VM NSG" "[$ErrorStatus] - Netinkama Deny-SQL-LocalServer taisyklė" "Red"
    }
}
elseif ($nicWarehouse) {
    Add-Result "VM NSG" "[$MissingStatus] - VM-Sandelis NIC neturi NSG" "Red"
}
else {
    Add-Result "VM NSG" "[$MissingStatus] - VM-Sandelis nerastas" "Red"
}

# ============================================================
# GALUTINIS REZULTATAS
# ============================================================

$date = Get-Date -Format "yyyy-MM-dd HH:mm"

Write-Host ""
Write-Host "--- $($Msg.FinalResult) ---" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Gray
Write-Host $Setup.HeaderTitle
Write-Host $LabName -ForegroundColor Yellow
Write-Host "$($Msg.Date): $date"
Write-Host "$($Msg.Student): $($Setup.StudentEmail)"
Write-Host "$($Msg.ScriptVersion): $($Setup.ScriptVersion)"
Write-Host "==================================================" -ForegroundColor Gray

# ============================================================
# REZULTATŲ FORMATAVIMAS
# ============================================================

$i = 1

foreach ($res in $resourceResults) {
    if ($res.Name -match "^ -") {
        $label = "   $($res.Name):"
    }
    else {
        $label = "$i. $($res.Name):"
        $i++
    }

    $targetWidth = 30
    $neededSpaces = $targetWidth - $label.Length
    if ($neededSpaces -lt 1) { $neededSpaces = 1 }

    $padding = " " * $neededSpaces

    Write-Host "$label$padding" -NoNewline
    Write-Host $res.Text -ForegroundColor $res.Color
}

Write-Host "==================================================" -ForegroundColor Gray
Write-Host ""