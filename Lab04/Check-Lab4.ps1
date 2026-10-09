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
$Setup = Initialize-Lab `
    -LocalConfigUrl "https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/Lab04/Check-Lab4-config.json" `
    -Lang $Lang

$LocCfg  = $Setup.LocalConfig
$Check   = $LocCfg.Checks
$LabMsg  = $LocCfg.Messages
$Msg     = $Setup.Messages
$LabName = $LocCfg.LabName.$Lang

$OkStatus      = $Msg.Ok
$ErrorStatus   = $Msg.Error
$MissingStatus = $LabMsg.Missing.$Lang
$WarningStatus = if ($Msg.Warning) { $Msg.Warning } else { $LabMsg.Warning.$Lang }

$resourceResults = @()

# ============================================================
# PAGALBINES FUNKCIJOS
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

function Get-LanguageValues {
    param ($ValueSet)

    @($ValueSet.LT, $ValueSet.EN) |
        Where-Object { $_ } |
        Select-Object -Unique
}

function Test-LanguagePattern {
    param (
        [string]$Value,
        $PatternSet
    )

    foreach ($pattern in (Get-LanguageValues $PatternSet)) {
        if ($Value -match $pattern) { return $true }
    }

    return $false
}

function Test-LanguageName {
    param (
        [string]$Value,
        $NameSet
    )

    return (Get-LanguageValues $NameSet) -contains $Value
}

# ============================================================
# A. RESOURCE GROUPS
# Priimami ir LT, ir EN pavadinimai nepriklausomai nuo checkerio kalbos.
# ============================================================

$allRGs = @(Get-AzResourceGroup)

$rgInfra = $allRGs |
    Where-Object { Test-LanguagePattern $_.ResourceGroupName $LocCfg.ResourceGroups.Infrastructure } |
    Select-Object -First 1

$rgAdmin = $allRGs |
    Where-Object { Test-LanguagePattern $_.ResourceGroupName $LocCfg.ResourceGroups.Administration } |
    Select-Object -First 1

$rgWarehouse = $allRGs |
    Where-Object { Test-LanguagePattern $_.ResourceGroupName $LocCfg.ResourceGroups.Warehouse } |
    Select-Object -First 1

$foundRGs = @($rgInfra, $rgAdmin, $rgWarehouse | Where-Object { $_ }).Count
$lab04RGs = @($allRGs | Where-Object { $_.ResourceGroupName -match '^RG-LAB04-' })

if ($rgInfra -and $rgAdmin -and $rgWarehouse) {
    Add-Result $Check.ResourceGroups.$Lang "[$OkStatus] - 3/3" "Green"
}
elseif ($lab04RGs.Count -ge 3) {
    $text = $LabMsg.FoundGroups.$Lang -f $foundRGs
    Add-Result $Check.ResourceGroups.$Lang "[$WarningStatus] - $text; $($LabMsg.RgNamesWarning.$Lang)" "Yellow"
}
else {
    $text = $LabMsg.FoundGroups.$Lang -f $foundRGs
    Add-Result $Check.ResourceGroups.$Lang "[$ErrorStatus] - $text" "Red"
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
        Add-Result $Check.VNetAdmin.$Lang "[$ErrorStatus] - Address space: $actual" "Red"
    }
    else {
        $details = @()
        $hasWarning = $false

        if ($frontEnd -and $frontEnd.AddressPrefix -eq $LocCfg.Networks.Admin.Subnets.FrontEnd.Prefix) {
            $details += "FrontEnd $($frontEnd.AddressPrefix)"
        }
        else {
            $details += "FrontEnd $($LabMsg.SubnetIncorrect.$Lang)"
            $hasWarning = $true
        }

        if ($backEnd -and $backEnd.AddressPrefix -eq $LocCfg.Networks.Admin.Subnets.BackEnd.Prefix) {
            $details += "BackEnd $($backEnd.AddressPrefix)"
        }
        else {
            $details += "BackEnd $($LabMsg.SubnetIncorrect.$Lang)"
            $hasWarning = $true
        }

        if ($hasWarning) {
            Add-Result $Check.VNetAdmin.$Lang "[$WarningStatus] - $($LocCfg.Networks.Admin.AddressSpace); $($details -join '; ')" "Yellow"
        }
        else {
            Add-Result $Check.VNetAdmin.$Lang "[$OkStatus] - $($LocCfg.Networks.Admin.AddressSpace); $($details -join '; ')" "Green"
        }
    }
}
else {
    Add-Result $Check.VNetAdmin.$Lang "[$MissingStatus] - $($LabMsg.NetworkNotFound.$Lang)" "Red"
}

# ============================================================
# C. VNET-WAREHOUSE / VNET-SANDELIS
# ============================================================

$warehouseVnetNames = Get-LanguageValues $LocCfg.Networks.Warehouse.Names
$warehouseSubnetNames = Get-LanguageValues $LocCfg.Networks.Warehouse.Subnets.Servers.Names

$vnetWarehouse = $allVNets |
    Where-Object { $warehouseVnetNames -contains $_.Name } |
    Select-Object -First 1

if ($vnetWarehouse) {
    $warehouseAddressOk = $vnetWarehouse.AddressSpace.AddressPrefixes -contains $LocCfg.Networks.Warehouse.AddressSpace

    $serverSubnet = $vnetWarehouse.Subnets |
        Where-Object { $warehouseSubnetNames -contains $_.Name } |
        Select-Object -First 1

    if (-not $warehouseAddressOk) {
        $actual = $vnetWarehouse.AddressSpace.AddressPrefixes -join ", "
        Add-Result $Check.VNetWarehouse.$Lang "[$ErrorStatus] - Address space: $actual" "Red"
    }
    elseif ($serverSubnet -and $serverSubnet.AddressPrefix -eq $LocCfg.Networks.Warehouse.Subnets.Servers.Prefix) {
        Add-Result $Check.VNetWarehouse.$Lang "[$OkStatus] - $($LocCfg.Networks.Warehouse.AddressSpace); Servers $($serverSubnet.AddressPrefix)" "Green"
    }
    else {
        Add-Result $Check.VNetWarehouse.$Lang "[$WarningStatus] - $($LocCfg.Networks.Warehouse.AddressSpace); Servers $($LabMsg.SubnetIncorrect.$Lang)" "Yellow"
    }
}
else {
    Add-Result $Check.VNetWarehouse.$Lang "[$MissingStatus] - $($LabMsg.NetworkNotFound.$Lang)" "Red"
}

# ============================================================
# D. VIRTUAL MACHINES
# ============================================================

$allVMs = @(Get-AzVM)

$vmAdmin = $allVMs |
    Where-Object Name -EQ $LocCfg.VirtualMachines.Admin |
    Select-Object -First 1

$warehouseVmNames = Get-LanguageValues $LocCfg.VirtualMachines.Warehouse

$vmWarehouse = $allVMs |
    Where-Object { $warehouseVmNames -contains $_.Name } |
    Select-Object -First 1

$nicAdmin = Get-NicFromVM $vmAdmin
$nicWarehouse = Get-NicFromVM $vmWarehouse

if ($vmAdmin -and $nicAdmin) {
    $adminIp = $nicAdmin.IpConfigurations[0].PrivateIpAddress
    $adminSubnetId = $nicAdmin.IpConfigurations[0].Subnet.Id

    $correctRG = Test-LanguagePattern $vmAdmin.ResourceGroupName $LocCfg.ResourceGroups.Administration
    $correctSubnet = $adminSubnetId -match "/virtualNetworks/VNet-Admin/subnets/VNet-Admin-FrontEnd$"

    if ($correctRG -and $correctSubnet) {
        Add-Result $Check.VmAdmin.$Lang "[$OkStatus] - $adminIp" "Green"
    }
    elseif ($correctSubnet -and $vmAdmin.ResourceGroupName -match '^RG-LAB04-') {
        Add-Result $Check.VmAdmin.$Lang "[$WarningStatus] - $($LabMsg.VmRgWarning.$Lang) ($adminIp)" "Yellow"
    }
    else {
        Add-Result $Check.VmAdmin.$Lang "[$ErrorStatus] - $($LabMsg.WrongRgOrSubnet.$Lang) ($adminIp)" "Red"
    }
}
else {
    Add-Result $Check.VmAdmin.$Lang "[$MissingStatus] - $($LabMsg.ServerNotFound.$Lang)" "Red"
}

if ($vmWarehouse -and $nicWarehouse) {
    $warehouseIp = $nicWarehouse.IpConfigurations[0].PrivateIpAddress
    $warehouseSubnetId = $nicWarehouse.IpConfigurations[0].Subnet.Id

    $correctRG = Test-LanguagePattern $vmWarehouse.ResourceGroupName $LocCfg.ResourceGroups.Warehouse
    $correctSubnet = $false

    foreach ($vnetName in $warehouseVnetNames) {
        foreach ($subnetName in $warehouseSubnetNames) {
            $escapedVnet = [regex]::Escape($vnetName)
            $escapedSubnet = [regex]::Escape($subnetName)

            if ($warehouseSubnetId -match "/virtualNetworks/$escapedVnet/subnets/$escapedSubnet$") {
                $correctSubnet = $true
                break
            }
        }
        if ($correctSubnet) { break }
    }

    if ($correctRG -and $correctSubnet) {
        Add-Result $Check.VmWarehouse.$Lang "[$OkStatus] - $warehouseIp" "Green"
    }
    elseif ($correctSubnet -and $vmWarehouse.ResourceGroupName -match '^RG-LAB04-') {
        Add-Result $Check.VmWarehouse.$Lang "[$WarningStatus] - $($LabMsg.VmRgWarning.$Lang) ($warehouseIp)" "Yellow"
    }
    else {
        Add-Result $Check.VmWarehouse.$Lang "[$ErrorStatus] - $($LabMsg.WrongRgOrSubnet.$Lang) ($warehouseIp)" "Red"
    }
}
else {
    Add-Result $Check.VmWarehouse.$Lang "[$MissingStatus] - $($LabMsg.ServerNotFound.$Lang)" "Red"
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
        Add-Result $Check.Peering.$Lang "[$OkStatus] - $($LabMsg.PeeringConnected.$Lang)" "Green"
    }
    else {
        Add-Result $Check.Peering.$Lang "[$ErrorStatus] - $($LabMsg.PeeringNotConnected.$Lang)" "Red"
    }
}
else {
    Add-Result $Check.Peering.$Lang "[$MissingStatus] - $($LabMsg.MissingVnet.$Lang)" "Red"
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
        Add-Result $Check.Asg.$Lang "[$OkStatus] - $($LabMsg.VmAssigned.$Lang)" "Green"
    }
    else {
        Add-Result $Check.Asg.$Lang "[$ErrorStatus] - $($LabMsg.VmNotAssigned.$Lang)" "Red"
    }
}
elseif ($asg) {
    Add-Result $Check.Asg.$Lang "[$ErrorStatus] - $($LabMsg.AsgVmMissing.$Lang)" "Red"
}
else {
    Add-Result $Check.Asg.$Lang "[$MissingStatus] - $($LabMsg.AsgMissing.$Lang)" "Red"
}

# ============================================================
# G. SUBNET NSG
# ============================================================

$subnetNsgNames = Get-LanguageValues $LocCfg.SubnetNSG.Names

$subnetNsg = Get-AzNetworkSecurityGroup -ErrorAction SilentlyContinue |
    Where-Object { $subnetNsgNames -contains $_.Name } |
    Select-Object -First 1

$subnetNsgAssociated = $false

if ($serverSubnet -and $serverSubnet.NetworkSecurityGroup -and $subnetNsg) {
    $subnetNsgAssociated = $serverSubnet.NetworkSecurityGroup.Id -eq $subnetNsg.Id
}

if (-not $subnetNsg) {
    Add-Result $Check.SubnetNsg.$Lang "[$MissingStatus] - $($LocCfg.SubnetNSG.Names.$Lang)" "Red"
}
elseif (-not $subnetNsgAssociated) {
    Add-Result $Check.SubnetNsg.$Lang "[$ErrorStatus] - $($LabMsg.SubnetNsgNotAssociated.$Lang)" "Red"
}
else {
    $sqlRule = $subnetNsg.SecurityRules |
        Where-Object Name -EQ $LocCfg.SubnetNSG.SqlRule.Name |
        Select-Object -First 1

    $sqlRuleExactName = [bool]$sqlRule

    if (-not $sqlRule) {
        $sqlRule = $subnetNsg.SecurityRules |
            Where-Object {
                $_.Access -eq $LocCfg.SubnetNSG.SqlRule.Access -and
                $_.Priority -eq $LocCfg.SubnetNSG.SqlRule.Priority -and
                $_.Direction -eq "Inbound" -and
                (Test-PortRule $_ $LocCfg.SubnetNSG.SqlRule.Port)
            } |
            Select-Object -First 1
    }

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
        $sqlRule.Direction -eq "Inbound" -and
        $sqlPortOk -and
        $sqlAsgOk

    $pingRule = $subnetNsg.SecurityRules |
        Where-Object Name -EQ $LocCfg.SubnetNSG.PingRule.Name |
        Select-Object -First 1

    $pingRuleExactName = [bool]$pingRule

    if (-not $pingRule) {
        $pingRule = $subnetNsg.SecurityRules |
            Where-Object {
                $_.Access -eq $LocCfg.SubnetNSG.PingRule.Access -and
                $_.Priority -eq $LocCfg.SubnetNSG.PingRule.Priority -and
                $_.Direction -eq "Inbound" -and
                $_.Protocol -in @("Icmp", "IcmpV4", "ICMP", "ICMPv4")
            } |
            Select-Object -First 1
    }

    $pingProtocolOk = $false
    if ($pingRule) {
        $pingProtocolOk = $pingRule.Protocol -in @("Icmp", "IcmpV4", "ICMP", "ICMPv4")
    }

    $pingAsgOk = $false
    if ($pingRule -and $asg) {
        $pingAsgIds = @($pingRule.DestinationApplicationSecurityGroups.Id)
        $pingAsgOk = $pingAsgIds -contains $asg.Id
    }

    $pingOk =
        $pingRule -and
        $pingRule.Access -eq $LocCfg.SubnetNSG.PingRule.Access -and
        $pingRule.Priority -eq $LocCfg.SubnetNSG.PingRule.Priority -and
        $pingRule.Direction -eq "Inbound" -and
        $pingProtocolOk -and
        $pingAsgOk

    if ($sqlOk -and $pingOk) {
        if ($sqlRuleExactName -and $pingRuleExactName) {
            Add-Result $Check.SubnetNsg.$Lang "[$OkStatus] - Allow-SQL, Allow-Ping" "Green"
        }
        else {
            $actualNames = @($sqlRule.Name, $pingRule.Name) -join ", "
            Add-Result $Check.SubnetNsg.$Lang "[$WarningStatus] - $actualNames; $($LabMsg.RuleNameWarning.$Lang)" "Yellow"
        }
    }
    else {
        $problems = @()

        if (-not $sqlOk) { $problems += "Allow-SQL" }
        if (-not $pingOk) { $problems += "Allow-Ping" }

        Add-Result $Check.SubnetNsg.$Lang "[$ErrorStatus] - $($LabMsg.CheckRules.$Lang): $($problems -join ', ')" "Red"
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

    $denyRuleNames = Get-LanguageValues $LocCfg.VmNSG.Rule.Name

    $denyRule = $vmNsg.SecurityRules |
        Where-Object { $denyRuleNames -contains $_.Name } |
        Select-Object -First 1

    $denyRuleExactName = [bool]$denyRule

    if (-not $denyRule) {
        $denyRule = $vmNsg.SecurityRules |
            Where-Object {
                $_.Access -eq $LocCfg.VmNSG.Rule.Access -and
                $_.Priority -eq $LocCfg.VmNSG.Rule.Priority -and
                $_.Direction -eq "Inbound" -and
                (Test-PortRule $_ $LocCfg.VmNSG.Rule.Port)
            } |
            Select-Object -First 1
    }

    $denyPortOk = Test-PortRule $denyRule $LocCfg.VmNSG.Rule.Port

    $denyOk =
        $denyRule -and
        $denyRule.Access -eq $LocCfg.VmNSG.Rule.Access -and
        $denyRule.Priority -eq $LocCfg.VmNSG.Rule.Priority -and
        $denyRule.Direction -eq "Inbound" -and
        $denyPortOk

    if ($denyOk) {
        if ($denyRuleExactName) {
            Add-Result $Check.VmNsg.$Lang "[$OkStatus] - $($denyRule.Name) (1433, Priority 400)" "Green"
        }
        else {
            Add-Result $Check.VmNsg.$Lang "[$WarningStatus] - $($denyRule.Name) (1433, Priority 400); $($LabMsg.RuleNameWarning.$Lang)" "Yellow"
        }
    }
    else {
        Add-Result $Check.VmNsg.$Lang "[$ErrorStatus] - $($LabMsg.WrongDenyRule.$Lang)" "Red"
    }
}
elseif ($nicWarehouse) {
    Add-Result $Check.VmNsg.$Lang "[$MissingStatus] - $($LabMsg.NicNoNsg.$Lang)" "Red"
}
else {
    Add-Result $Check.VmNsg.$Lang "[$MissingStatus] - $($LabMsg.ServerNotFound.$Lang)" "Red"
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
# REZULTATU FORMATAVIMAS
# ============================================================

$i = 1

foreach ($res in $resourceResults) {
    $label = "$i. $($res.Name):"
    $i++

    $targetWidth = 30
    $neededSpaces = $targetWidth - $label.Length
    if ($neededSpaces -lt 1) { $neededSpaces = 1 }

    $padding = " " * $neededSpaces

    Write-Host "$label$padding" -NoNewline
    Write-Host $res.Text -ForegroundColor $res.Color
}

Write-Host "==================================================" -ForegroundColor Gray
Write-Host ""
