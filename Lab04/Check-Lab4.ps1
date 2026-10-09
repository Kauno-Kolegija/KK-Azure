# ============================================================
# LAB 4 - Azure Networking validation
# ============================================================

# --- 1. KALBA ---
if ($Lang -notin @("LT", "EN")) { $Lang = "LT" }

# --- 2. UZKRAUNAME BENDRAS FUNKCIJAS ---
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

# --- 3. INICIJUOJAME DARBA ---
$Setup = Initialize-Lab -LocalConfigUrl "https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/Lab04/Check-Lab4-config.json" -Lang $Lang

$LocCfg = $Setup.LocalConfig
$Check = $LocCfg.Checks
$LabMsg = $LocCfg.Messages
$Msg = $Setup.Messages
$LabName = $LocCfg.LabName.$Lang
$results = @()

# ============================================================
# PAGALBINES FUNKCIJOS
# ============================================================

function Get-NicFromVM {
    param ($VM)

    if (-not $VM -or -not $VM.NetworkProfile.NetworkInterfaces[0].Id) { return $null }

    $parts = $VM.NetworkProfile.NetworkInterfaces[0].Id -split '/'
    if ($parts.Count -lt 9) { return $null }

    Get-AzNetworkInterface -ResourceGroupName $parts[4] -Name $parts[-1] -ErrorAction SilentlyContinue
}

function Test-PortRule {
    param ($Rule, [string]$Port)

    if (-not $Rule) { return $false }

    $ports = @()
    if ($Rule.DestinationPortRange)  { $ports += @($Rule.DestinationPortRange) }
    if ($Rule.DestinationPortRanges) { $ports += @($Rule.DestinationPortRanges) }

    return ($ports -contains $Port)
}

function Get-LanguageValues {
    param ($ValueSet)
    @($ValueSet.LT, $ValueSet.EN) | Where-Object { $_ } | Select-Object -Unique
}

function Test-LanguagePattern {
    param ([string]$Value, $PatternSet)

    foreach ($pattern in (Get-LanguageValues $PatternSet)) {
        if ($Value -match $pattern) { return $true }
    }
    return $false
}

# ============================================================
# A. RESOURCE GROUPS
# Priimami LT ir EN pavadinimai nepriklausomai nuo checkerio kalbos
# ============================================================

try {
    $allRGs = @(Get-AzResourceGroup -ErrorAction Stop)

    $infraPatterns = Get-LanguageValues $LocCfg.ResourceGroups.Infrastructure
    $adminPatterns = Get-LanguageValues $LocCfg.ResourceGroups.Administration
    $warehousePatterns = Get-LanguageValues $LocCfg.ResourceGroups.Warehouse

    $rgInfra = $null
    foreach ($pattern in $infraPatterns) {
        $m = Find-PatternMatch -Items $allRGs -Property "ResourceGroupName" -Pattern $pattern
        if ($m.First) { $rgInfra = $m.First; break }
    }

    $rgAdmin = $null
    foreach ($pattern in $adminPatterns) {
        $m = Find-PatternMatch -Items $allRGs -Property "ResourceGroupName" -Pattern $pattern
        if ($m.First) { $rgAdmin = $m.First; break }
    }

    $rgWarehouse = $null
    foreach ($pattern in $warehousePatterns) {
        $m = Find-PatternMatch -Items $allRGs -Property "ResourceGroupName" -Pattern $pattern
        if ($m.First) { $rgWarehouse = $m.First; break }
    }

    $foundRGs = @($rgInfra, $rgAdmin, $rgWarehouse | Where-Object { $_ }).Count
    $lab04Match = Find-PatternMatch -Items $allRGs -Property "ResourceGroupName" -Pattern '^RG-LAB04-'

    if ($foundRGs -eq 3) {
        Add-LabResult -Results ([ref]$results) -Name $Check.ResourceGroups.$Lang -Status "OK" -Message "3/3" -Messages $Msg
    }
    elseif ($lab04Match.Count -ge 3) {
        $text = $LabMsg.FoundGroups.$Lang -f $foundRGs
        Add-LabResult -Results ([ref]$results) -Name $Check.ResourceGroups.$Lang -Status "WARNING" -Message "$text; $($LabMsg.RgNamesWarning.$Lang)" -Messages $Msg
    }
    else {
        $text = $LabMsg.FoundGroups.$Lang -f $foundRGs
        Add-LabResult -Results ([ref]$results) -Name $Check.ResourceGroups.$Lang -Status "ERROR" -Message $text -Messages $Msg
    }
}
catch {
    $allRGs = @()
    $rgInfra = $rgAdmin = $rgWarehouse = $null
    Add-LabResult -Results ([ref]$results) -Name $Check.ResourceGroups.$Lang -Status "WARNING" -Message $Msg.CheckFailed -Messages $Msg
}

# ============================================================
# B. VNET-ADMIN
# ============================================================

try {
    $allVNets = @(Get-AzVirtualNetwork -ErrorAction Stop)
    $adminMatch = Find-PatternMatch -Items $allVNets -Property "Name" -Pattern "^$([regex]::Escape($LocCfg.Networks.Admin.Name))$"
    $vnetAdmin = $adminMatch.First

    if ($vnetAdmin) {
        $adminAddressOk = $vnetAdmin.AddressSpace.AddressPrefixes -contains $LocCfg.Networks.Admin.AddressSpace
        $frontEnd = $vnetAdmin.Subnets | Where-Object Name -EQ $LocCfg.Networks.Admin.Subnets.FrontEnd.Name | Select-Object -First 1
        $backEnd = $vnetAdmin.Subnets | Where-Object Name -EQ $LocCfg.Networks.Admin.Subnets.BackEnd.Name | Select-Object -First 1

        if (-not $adminAddressOk) {
            Add-LabResult -Results ([ref]$results) -Name $Check.VNetAdmin.$Lang -Status "ERROR" -Message "Address space: $($vnetAdmin.AddressSpace.AddressPrefixes -join ', ')" -Messages $Msg
        }
        else {
            $details = @()
            $warning = $false

            if ($frontEnd -and $frontEnd.AddressPrefix -eq $LocCfg.Networks.Admin.Subnets.FrontEnd.Prefix) { $details += "FrontEnd $($frontEnd.AddressPrefix)" }
            else { $details += "FrontEnd $($LabMsg.SubnetIncorrect.$Lang)"; $warning = $true }

            if ($backEnd -and $backEnd.AddressPrefix -eq $LocCfg.Networks.Admin.Subnets.BackEnd.Prefix) { $details += "BackEnd $($backEnd.AddressPrefix)" }
            else { $details += "BackEnd $($LabMsg.SubnetIncorrect.$Lang)"; $warning = $true }

            Add-LabResult -Results ([ref]$results) -Name $Check.VNetAdmin.$Lang -Status $(if ($warning) { "WARNING" } else { "OK" }) -Message "$($LocCfg.Networks.Admin.AddressSpace); $($details -join '; ')" -Messages $Msg
        }
    }
    else {
        Add-LabResult -Results ([ref]$results) -Name $Check.VNetAdmin.$Lang -Status "ERROR" -Message $LabMsg.NetworkNotFound.$Lang -Messages $Msg
    }
}
catch {
    $allVNets = @()
    $vnetAdmin = $null
    Add-LabResult -Results ([ref]$results) -Name $Check.VNetAdmin.$Lang -Status "WARNING" -Message $Msg.CheckFailed -Messages $Msg
}

# ============================================================
# C. VNET-WAREHOUSE / VNET-SANDELIS
# ============================================================

$warehouseVnetNames = Get-LanguageValues $LocCfg.Networks.Warehouse.Names
$warehouseSubnetNames = Get-LanguageValues $LocCfg.Networks.Warehouse.Subnets.Servers.Names
$vnetWarehouse = $allVNets | Where-Object { $warehouseVnetNames -contains $_.Name } | Select-Object -First 1
$serverSubnet = $null

if ($vnetWarehouse) {
    $warehouseAddressOk = $vnetWarehouse.AddressSpace.AddressPrefixes -contains $LocCfg.Networks.Warehouse.AddressSpace
    $serverSubnet = $vnetWarehouse.Subnets | Where-Object { $warehouseSubnetNames -contains $_.Name } | Select-Object -First 1

    if (-not $warehouseAddressOk) {
        Add-LabResult -Results ([ref]$results) -Name $Check.VNetWarehouse.$Lang -Status "ERROR" -Message "Address space: $($vnetWarehouse.AddressSpace.AddressPrefixes -join ', ')" -Messages $Msg
    }
    elseif ($serverSubnet -and $serverSubnet.AddressPrefix -eq $LocCfg.Networks.Warehouse.Subnets.Servers.Prefix) {
        Add-LabResult -Results ([ref]$results) -Name $Check.VNetWarehouse.$Lang -Status "OK" -Message "$($LocCfg.Networks.Warehouse.AddressSpace); Servers $($serverSubnet.AddressPrefix)" -Messages $Msg
    }
    else {
        Add-LabResult -Results ([ref]$results) -Name $Check.VNetWarehouse.$Lang -Status "WARNING" -Message "$($LocCfg.Networks.Warehouse.AddressSpace); Servers $($LabMsg.SubnetIncorrect.$Lang)" -Messages $Msg
    }
}
else {
    Add-LabResult -Results ([ref]$results) -Name $Check.VNetWarehouse.$Lang -Status "ERROR" -Message $LabMsg.NetworkNotFound.$Lang -Messages $Msg
}

# ============================================================
# D. VIRTUAL MACHINES
# ============================================================

try { $allVMs = @(Get-AzVM -ErrorAction Stop) }
catch { $allVMs = @() }

$vmAdmin = $allVMs | Where-Object Name -EQ $LocCfg.VirtualMachines.Admin | Select-Object -First 1
$warehouseVmNames = Get-LanguageValues $LocCfg.VirtualMachines.Warehouse
$vmWarehouse = $allVMs | Where-Object { $warehouseVmNames -contains $_.Name } | Select-Object -First 1

$nicAdmin = Get-NicFromVM $vmAdmin
$nicWarehouse = Get-NicFromVM $vmWarehouse

if ($vmAdmin -and $nicAdmin) {
    $adminIp = $nicAdmin.IpConfigurations[0].PrivateIpAddress
    $correctRG = Test-LanguagePattern $vmAdmin.ResourceGroupName $LocCfg.ResourceGroups.Administration
    $correctSubnet = $nicAdmin.IpConfigurations[0].Subnet.Id -match "/virtualNetworks/VNet-Admin/subnets/VNet-Admin-FrontEnd$"

    if ($correctRG -and $correctSubnet) {
        Add-LabResult -Results ([ref]$results) -Name $Check.VmAdmin.$Lang -Status "OK" -Message $adminIp -Messages $Msg
    }
    elseif ($correctSubnet -and $vmAdmin.ResourceGroupName -match '^RG-LAB04-') {
        Add-LabResult -Results ([ref]$results) -Name $Check.VmAdmin.$Lang -Status "WARNING" -Message "$($LabMsg.VmRgWarning.$Lang) ($adminIp)" -Messages $Msg
    }
    else {
        Add-LabResult -Results ([ref]$results) -Name $Check.VmAdmin.$Lang -Status "ERROR" -Message "$($LabMsg.WrongRgOrSubnet.$Lang) ($adminIp)" -Messages $Msg
    }
}
else {
    Add-LabResult -Results ([ref]$results) -Name $Check.VmAdmin.$Lang -Status "ERROR" -Message $LabMsg.ServerNotFound.$Lang -Messages $Msg
}

if ($vmWarehouse -and $nicWarehouse) {
    $warehouseIp = $nicWarehouse.IpConfigurations[0].PrivateIpAddress
    $warehouseSubnetId = $nicWarehouse.IpConfigurations[0].Subnet.Id
    $correctRG = Test-LanguagePattern $vmWarehouse.ResourceGroupName $LocCfg.ResourceGroups.Warehouse
    $correctSubnet = $false

    foreach ($vnetName in $warehouseVnetNames) {
        foreach ($subnetName in $warehouseSubnetNames) {
            if ($warehouseSubnetId -match "/virtualNetworks/$([regex]::Escape($vnetName))/subnets/$([regex]::Escape($subnetName))$") {
                $correctSubnet = $true
                break
            }
        }
        if ($correctSubnet) { break }
    }

    if ($correctRG -and $correctSubnet) {
        Add-LabResult -Results ([ref]$results) -Name $Check.VmWarehouse.$Lang -Status "OK" -Message $warehouseIp -Messages $Msg
    }
    elseif ($correctSubnet -and $vmWarehouse.ResourceGroupName -match '^RG-LAB04-') {
        Add-LabResult -Results ([ref]$results) -Name $Check.VmWarehouse.$Lang -Status "WARNING" -Message "$($LabMsg.VmRgWarning.$Lang) ($warehouseIp)" -Messages $Msg
    }
    else {
        Add-LabResult -Results ([ref]$results) -Name $Check.VmWarehouse.$Lang -Status "ERROR" -Message "$($LabMsg.WrongRgOrSubnet.$Lang) ($warehouseIp)" -Messages $Msg
    }
}
else {
    Add-LabResult -Results ([ref]$results) -Name $Check.VmWarehouse.$Lang -Status "ERROR" -Message $LabMsg.ServerNotFound.$Lang -Messages $Msg
}

# ============================================================
# E. VNET PEERING
# ============================================================

if ($vnetAdmin -and $vnetWarehouse) {
    $adminToWarehouse = $vnetAdmin.VirtualNetworkPeerings | Where-Object { $_.RemoteVirtualNetwork.Id -eq $vnetWarehouse.Id -and $_.PeeringState -eq "Connected" } | Select-Object -First 1
    $warehouseToAdmin = $vnetWarehouse.VirtualNetworkPeerings | Where-Object { $_.RemoteVirtualNetwork.Id -eq $vnetAdmin.Id -and $_.PeeringState -eq "Connected" } | Select-Object -First 1

    if ($adminToWarehouse -and $warehouseToAdmin) {
        Add-LabResult -Results ([ref]$results) -Name $Check.Peering.$Lang -Status "OK" -Message $LabMsg.PeeringConnected.$Lang -Messages $Msg
    }
    else {
        Add-LabResult -Results ([ref]$results) -Name $Check.Peering.$Lang -Status "ERROR" -Message $LabMsg.PeeringNotConnected.$Lang -Messages $Msg
    }
}
else {
    Add-LabResult -Results ([ref]$results) -Name $Check.Peering.$Lang -Status "ERROR" -Message $LabMsg.MissingVnet.$Lang -Messages $Msg
}

# ============================================================
# F. APPLICATION SECURITY GROUP
# ============================================================

$asg = Get-AzApplicationSecurityGroup -ErrorAction SilentlyContinue | Where-Object Name -EQ $LocCfg.ApplicationSecurityGroup | Select-Object -First 1

if ($asg -and $nicWarehouse) {
    $asgIds = @($nicWarehouse.IpConfigurations.ApplicationSecurityGroups.Id)
    if ($asgIds -contains $asg.Id) {
        Add-LabResult -Results ([ref]$results) -Name $Check.Asg.$Lang -Status "OK" -Message $LabMsg.VmAssigned.$Lang -Messages $Msg
    }
    else {
        Add-LabResult -Results ([ref]$results) -Name $Check.Asg.$Lang -Status "ERROR" -Message $LabMsg.VmNotAssigned.$Lang -Messages $Msg
    }
}
elseif ($asg) {
    Add-LabResult -Results ([ref]$results) -Name $Check.Asg.$Lang -Status "ERROR" -Message $LabMsg.AsgVmMissing.$Lang -Messages $Msg
}
else {
    Add-LabResult -Results ([ref]$results) -Name $Check.Asg.$Lang -Status "ERROR" -Message $LabMsg.AsgMissing.$Lang -Messages $Msg
}

# ============================================================
# G. SUBNET NSG
# ============================================================

$subnetNsgNames = Get-LanguageValues $LocCfg.SubnetNSG.Names
$subnetNsg = Get-AzNetworkSecurityGroup -ErrorAction SilentlyContinue | Where-Object { $subnetNsgNames -contains $_.Name } | Select-Object -First 1
$subnetNsgAssociated = $serverSubnet -and $serverSubnet.NetworkSecurityGroup -and $subnetNsg -and ($serverSubnet.NetworkSecurityGroup.Id -eq $subnetNsg.Id)

if (-not $subnetNsg) {
    Add-LabResult -Results ([ref]$results) -Name $Check.SubnetNsg.$Lang -Status "ERROR" -Message $LocCfg.SubnetNSG.Names.$Lang -Messages $Msg
}
elseif (-not $subnetNsgAssociated) {
    Add-LabResult -Results ([ref]$results) -Name $Check.SubnetNsg.$Lang -Status "ERROR" -Message $LabMsg.SubnetNsgNotAssociated.$Lang -Messages $Msg
}
else {
    $sqlRule = $subnetNsg.SecurityRules | Where-Object Name -EQ $LocCfg.SubnetNSG.SqlRule.Name | Select-Object -First 1
    $sqlRuleExactName = [bool]$sqlRule

    if (-not $sqlRule) {
        $sqlRule = $subnetNsg.SecurityRules | Where-Object {
            $_.Access -eq $LocCfg.SubnetNSG.SqlRule.Access -and
            $_.Priority -eq $LocCfg.SubnetNSG.SqlRule.Priority -and
            $_.Direction -eq "Inbound" -and
            (Test-PortRule $_ $LocCfg.SubnetNSG.SqlRule.Port)
        } | Select-Object -First 1
    }

    $sqlAsgIds = if ($sqlRule) { @($sqlRule.DestinationApplicationSecurityGroups.Id) } else { @() }
    $sqlOk = $sqlRule -and $sqlRule.Access -eq $LocCfg.SubnetNSG.SqlRule.Access -and $sqlRule.Priority -eq $LocCfg.SubnetNSG.SqlRule.Priority -and $sqlRule.Direction -eq "Inbound" -and (Test-PortRule $sqlRule $LocCfg.SubnetNSG.SqlRule.Port) -and ($asg -and $sqlAsgIds -contains $asg.Id)

    $pingRule = $subnetNsg.SecurityRules | Where-Object Name -EQ $LocCfg.SubnetNSG.PingRule.Name | Select-Object -First 1
    $pingRuleExactName = [bool]$pingRule

    if (-not $pingRule) {
        $pingRule = $subnetNsg.SecurityRules | Where-Object {
            $_.Access -eq $LocCfg.SubnetNSG.PingRule.Access -and
            $_.Priority -eq $LocCfg.SubnetNSG.PingRule.Priority -and
            $_.Direction -eq "Inbound" -and
            $_.Protocol -in @("Icmp", "IcmpV4", "ICMP", "ICMPv4")
        } | Select-Object -First 1
    }

    $pingAsgIds = if ($pingRule) { @($pingRule.DestinationApplicationSecurityGroups.Id) } else { @() }
    $pingOk = $pingRule -and $pingRule.Access -eq $LocCfg.SubnetNSG.PingRule.Access -and $pingRule.Priority -eq $LocCfg.SubnetNSG.PingRule.Priority -and $pingRule.Direction -eq "Inbound" -and $pingRule.Protocol -in @("Icmp", "IcmpV4", "ICMP", "ICMPv4") -and ($asg -and $pingAsgIds -contains $asg.Id)

    if ($sqlOk -and $pingOk) {
        if ($sqlRuleExactName -and $pingRuleExactName) {
            Add-LabResult -Results ([ref]$results) -Name $Check.SubnetNsg.$Lang -Status "OK" -Message "Allow-SQL, Allow-Ping" -Messages $Msg
        }
        else {
            Add-LabResult -Results ([ref]$results) -Name $Check.SubnetNsg.$Lang -Status "WARNING" -Message "$($sqlRule.Name), $($pingRule.Name); $($LabMsg.RuleNameWarning.$Lang)" -Messages $Msg
        }
    }
    else {
        $problems = @()
        if (-not $sqlOk) { $problems += "Allow-SQL" }
        if (-not $pingOk) { $problems += "Allow-Ping" }
        Add-LabResult -Results ([ref]$results) -Name $Check.SubnetNsg.$Lang -Status "ERROR" -Message "$($LabMsg.CheckRules.$Lang): $($problems -join ', ')" -Messages $Msg
    }
}

# ============================================================
# H. VM NIC NSG
# ============================================================

if ($nicWarehouse -and $nicWarehouse.NetworkSecurityGroup) {
    $parts = $nicWarehouse.NetworkSecurityGroup.Id -split '/'
    $vmNsg = Get-AzNetworkSecurityGroup -ResourceGroupName $parts[4] -Name $parts[-1] -ErrorAction SilentlyContinue
    $denyRuleNames = Get-LanguageValues $LocCfg.VmNSG.Rule.Name

    $denyRule = $vmNsg.SecurityRules | Where-Object { $denyRuleNames -contains $_.Name } | Select-Object -First 1
    $denyRuleExactName = [bool]$denyRule

    if (-not $denyRule) {
        $denyRule = $vmNsg.SecurityRules | Where-Object {
            $_.Access -eq $LocCfg.VmNSG.Rule.Access -and
            $_.Priority -eq $LocCfg.VmNSG.Rule.Priority -and
            $_.Direction -eq "Inbound" -and
            (Test-PortRule $_ $LocCfg.VmNSG.Rule.Port)
        } | Select-Object -First 1
    }

    $denyOk = $denyRule -and $denyRule.Access -eq $LocCfg.VmNSG.Rule.Access -and $denyRule.Priority -eq $LocCfg.VmNSG.Rule.Priority -and $denyRule.Direction -eq "Inbound" -and (Test-PortRule $denyRule $LocCfg.VmNSG.Rule.Port)

    if ($denyOk -and $denyRuleExactName) {
        Add-LabResult -Results ([ref]$results) -Name $Check.VmNsg.$Lang -Status "OK" -Message "$($denyRule.Name) (1433, Priority 400)" -Messages $Msg
    }
    elseif ($denyOk) {
        Add-LabResult -Results ([ref]$results) -Name $Check.VmNsg.$Lang -Status "WARNING" -Message "$($denyRule.Name) (1433, Priority 400); $($LabMsg.RuleNameWarning.$Lang)" -Messages $Msg
    }
    else {
        Add-LabResult -Results ([ref]$results) -Name $Check.VmNsg.$Lang -Status "ERROR" -Message $LabMsg.WrongDenyRule.$Lang -Messages $Msg
    }
}
elseif ($nicWarehouse) {
    Add-LabResult -Results ([ref]$results) -Name $Check.VmNsg.$Lang -Status "ERROR" -Message $LabMsg.NicNoNsg.$Lang -Messages $Msg
}
else {
    Add-LabResult -Results ([ref]$results) -Name $Check.VmNsg.$Lang -Status "ERROR" -Message $LabMsg.ServerNotFound.$Lang -Messages $Msg
}

# ============================================================
# GALUTINIS REZULTATAS
# ============================================================

Show-LabResults -Setup $Setup -LabName $LabName -Results $results -LabelWidth 30
