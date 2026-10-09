# ============================================================
# LAB 5 CHECKER - CLI NETWORKING
# ============================================================

# --- Užkrauname bendras funkcijas ---
try {
    if ($PSScriptRoot) {
        . (Join-Path $PSScriptRoot '../configs/common.ps1')
    } else {
        Invoke-RestMethod 'https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/configs/common.ps1' -ErrorAction Stop | Invoke-Expression
    }
} catch {
    Write-Error "Failed to load common functions."
    throw
}

if ($Lang -notin @("LT", "EN")) { $Lang = "LT" }

$Setup = Initialize-Lab -LocalConfigUrl "https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/Lab05/Check-Lab5-config.json" -Lang $Lang
$LocCfg = $Setup.LocalConfig
$Check = $LocCfg.Checks
$LabMsg = $LocCfg.Messages
$Msg = $Setup.Messages
$LabName = $LocCfg.LabName.$Lang
$results = @()

# ============================================================
# PAGALBINĖS FUNKCIJOS
# ============================================================

function Test-PortRule {
    param($Rule, [string]$Protocol, [string]$Port, [string]$Access)

    if (-not $Rule) { return $false }

    $ports = @()
    if ($Rule.DestinationPortRange)  { $ports += @($Rule.DestinationPortRange) }
    if ($Rule.DestinationPortRanges) { $ports += @($Rule.DestinationPortRanges) }

    return (
        $Rule.Protocol -ieq $Protocol -and
        $Rule.Access -ieq $Access -and
        $Rule.Direction -ieq "Inbound" -and
        $ports -contains $Port
    )
}

function Get-VMNic {
    param($VM)

    if (-not $VM -or -not $VM.NetworkProfile.NetworkInterfaces[0].Id) { return $null }

    $nicId = $VM.NetworkProfile.NetworkInterfaces[0].Id
    $parts = $nicId -split '/'
    if ($parts.Count -lt 9) { return $null }

    try {
        return Get-AzNetworkInterface -ResourceGroupName $parts[4] -Name $parts[-1] -ErrorAction Stop
    } catch {
        return $null
    }
}

function Test-TagValue {
    param($Tags, [string]$Name, [string]$ExpectedValue)

    if (-not $Tags -or -not $Tags.ContainsKey($Name)) { return $false }
    if ($ExpectedValue) { return $Tags[$Name] -eq $ExpectedValue }

    return -not [string]::IsNullOrWhiteSpace([string]$Tags[$Name])
}

# ============================================================
# 1. RESOURCE GROUP
# ============================================================

try {
    $allRGs = @(Get-AzResourceGroup -ErrorAction Stop)
    $rgMatch = Find-PatternMatch -Items $allRGs -Property "ResourceGroupName" -Pattern $LocCfg.ResourceGroup.Pattern
    $targetRG = $rgMatch.First

    if ($targetRG) {
        $status = if ($rgMatch.Count -gt 1) { "WARNING" } else { "OK" }
        $message = "$($targetRG.ResourceGroupName) ($($targetRG.Location))"
        if ($rgMatch.Count -gt 1) { $message += "; $($LabMsg.MultipleResourceGroups.$Lang)" }
        Add-LabResult -Results ([ref]$results) -Name $Check.ResourceGroup.$Lang -Status $status -Message $message -Messages $Msg
    } else {
        Add-LabResult -Results ([ref]$results) -Name $Check.ResourceGroup.$Lang -Status "ERROR" -Message $LabMsg.NotFound.$Lang -Messages $Msg
    }
}
catch {
    $targetRG = $null
    Add-LabResult -Results ([ref]$results) -Name $Check.ResourceGroup.$Lang -Status "WARNING" -Message $Msg.CheckFailed -Messages $Msg
}

if ($targetRG) {
    $rgName = $targetRG.ResourceGroupName

    # ========================================================
    # 2. VNET + WEBSUBNET
    # ========================================================

    try {
        $allVNets = @(Get-AzVirtualNetwork -ResourceGroupName $rgName -ErrorAction Stop)
        $vnetMatch = Find-PatternMatch -Items $allVNets -Property "Name" -Pattern $LocCfg.Network.VNetPattern
        $vnet = $vnetMatch.First
    } catch {
        $vnet = $null
    }

    if ($vnet) {
        $prefix = $vnet.Name -replace '-VNet$', ''
        $addressOk = $vnet.AddressSpace.AddressPrefixes -contains $LocCfg.Network.AddressSpace
        $webSubnet = $vnet.Subnets | Where-Object Name -EQ $LocCfg.Network.Subnet.Name | Select-Object -First 1
        $subnetOk = $webSubnet -and ($webSubnet.AddressPrefix -eq $LocCfg.Network.Subnet.Prefix -or $webSubnet.AddressPrefixes -contains $LocCfg.Network.Subnet.Prefix)

        $subnetPrefix = if ($webSubnet) { if ($webSubnet.AddressPrefix) { $webSubnet.AddressPrefix } else { $webSubnet.AddressPrefixes -join ", " } } else { "-" }
        $vnetInfo = "$($vnet.Name) - $($vnet.AddressSpace.AddressPrefixes -join ', '); WebSubnet $subnetPrefix"

        if ($addressOk -and $subnetOk) {
            Add-LabResult -Results ([ref]$results) -Name $Check.VNet.$Lang -Status "OK" -Message $vnetInfo -Messages $Msg
        } elseif (-not $addressOk) {
            Add-LabResult -Results ([ref]$results) -Name $Check.VNet.$Lang -Status "ERROR" -Message "$($LabMsg.WrongAddressSpace.$Lang); $vnetInfo" -Messages $Msg
        } else {
            Add-LabResult -Results ([ref]$results) -Name $Check.VNet.$Lang -Status "ERROR" -Message "$($LabMsg.WrongSubnet.$Lang); $vnetInfo" -Messages $Msg
        }
    } else {
        $prefix = $null
        $webSubnet = $null
        Add-LabResult -Results ([ref]$results) -Name $Check.VNet.$Lang -Status "ERROR" -Message $LabMsg.NotFound.$Lang -Messages $Msg
    }

    # ========================================================
    # 3. NSG + RULES
    # ========================================================

    try {
        $allNsgs = @(Get-AzNetworkSecurityGroup -ResourceGroupName $rgName -ErrorAction Stop)
        $expectedNsgName = if ($prefix) { "$prefix-NSG" } else { $null }

        if ($expectedNsgName) {
            $nsg = $allNsgs | Where-Object Name -EQ $expectedNsgName | Select-Object -First 1
        } else {
            $nsg = (Find-PatternMatch -Items $allNsgs -Property "Name" -Pattern $LocCfg.NSG.NamePattern).First
        }
    } catch {
        $nsg = $null
    }

    if ($nsg) {
        $webRule = $nsg.SecurityRules | Where-Object Name -EQ $LocCfg.NSG.WebRule.Name | Select-Object -First 1
        $webRuleExactName = [bool]$webRule
        if (-not $webRule) {
            $webRule = $nsg.SecurityRules | Where-Object { Test-PortRule $_ $LocCfg.NSG.WebRule.Protocol $LocCfg.NSG.WebRule.DestinationPort $LocCfg.NSG.WebRule.Access } | Select-Object -First 1
        }

        $rdpRule = $nsg.SecurityRules | Where-Object Name -EQ $LocCfg.NSG.RdpRule.Name | Select-Object -First 1
        $rdpRuleExactName = [bool]$rdpRule
        if (-not $rdpRule) {
            $rdpRule = $nsg.SecurityRules | Where-Object { Test-PortRule $_ $LocCfg.NSG.RdpRule.Protocol $LocCfg.NSG.RdpRule.DestinationPort $LocCfg.NSG.RdpRule.Access } | Select-Object -First 1
        }

        $webRuleOk = Test-PortRule $webRule $LocCfg.NSG.WebRule.Protocol $LocCfg.NSG.WebRule.DestinationPort $LocCfg.NSG.WebRule.Access
        $rdpRuleOk = Test-PortRule $rdpRule $LocCfg.NSG.RdpRule.Protocol $LocCfg.NSG.RdpRule.DestinationPort $LocCfg.NSG.RdpRule.Access

        $priorityOk = $webRule -and $rdpRule -and
            $webRule.Priority -ne $rdpRule.Priority -and
            $webRule.Priority -ge $LocCfg.NSG.Priority.Minimum -and
            $webRule.Priority -le $LocCfg.NSG.Priority.Maximum -and
            $rdpRule.Priority -ge $LocCfg.NSG.Priority.Minimum -and
            $rdpRule.Priority -le $LocCfg.NSG.Priority.Maximum

        $nsgAssociated = $webSubnet -and $webSubnet.NetworkSecurityGroup.Id -and ($webSubnet.NetworkSecurityGroup.Id -eq $nsg.Id)
        $nsgInfo = "$($nsg.Name); WEB:$($webRule.Priority); RDP:$($rdpRule.Priority)"

        if (-not $nsgAssociated) {
            Add-LabResult -Results ([ref]$results) -Name $Check.NSG.$Lang -Status "ERROR" -Message $LabMsg.NsgNotAssociated.$Lang -Messages $Msg
        } elseif (-not $webRuleOk -or -not $rdpRuleOk) {
            Add-LabResult -Results ([ref]$results) -Name $Check.NSG.$Lang -Status "ERROR" -Message $LabMsg.WrongNsgRules.$Lang -Messages $Msg
        } elseif (-not $priorityOk) {
            Add-LabResult -Results ([ref]$results) -Name $Check.NSG.$Lang -Status "ERROR" -Message $LabMsg.DuplicatePriority.$Lang -Messages $Msg
        } elseif (-not $webRuleExactName -or -not $rdpRuleExactName) {
            Add-LabResult -Results ([ref]$results) -Name $Check.NSG.$Lang -Status "WARNING" -Message "$nsgInfo; $($LabMsg.RuleNameWarning.$Lang)" -Messages $Msg
        } else {
            Add-LabResult -Results ([ref]$results) -Name $Check.NSG.$Lang -Status "OK" -Message $nsgInfo -Messages $Msg
        }
    } else {
        Add-LabResult -Results ([ref]$results) -Name $Check.NSG.$Lang -Status "ERROR" -Message $LabMsg.NotFound.$Lang -Messages $Msg
    }

    # ========================================================
    # 4. AVAILABILITY SET
    # ========================================================

    try {
        $allAvSets = @(Get-AzAvailabilitySet -ResourceGroupName $rgName -ErrorAction Stop)
        $expectedAvSetName = if ($prefix) { "$prefix-AvailabilitySet" } else { $null }

        if ($expectedAvSetName) {
            $avSet = $allAvSets | Where-Object Name -EQ $expectedAvSetName | Select-Object -First 1
        } else {
            $avSet = (Find-PatternMatch -Items $allAvSets -Property "Name" -Pattern $LocCfg.AvailabilitySet.NamePattern).First
        }
    } catch {
        $avSet = $null
    }

    if ($avSet) {
        $avSetOk = $avSet.PlatformFaultDomainCount -eq $LocCfg.AvailabilitySet.FaultDomains -and $avSet.PlatformUpdateDomainCount -eq $LocCfg.AvailabilitySet.UpdateDomains
        $avInfo = "$($avSet.Name); FD=$($avSet.PlatformFaultDomainCount); UD=$($avSet.PlatformUpdateDomainCount)"
        Add-LabResult -Results ([ref]$results) -Name $Check.AvailabilitySet.$Lang -Status $(if ($avSetOk) { "OK" } else { "WARNING" }) -Message $(if ($avSetOk) { $avInfo } else { "$($LabMsg.WrongAvailabilitySet.$Lang); $avInfo" }) -Messages $Msg
    } else {
        Add-LabResult -Results ([ref]$results) -Name $Check.AvailabilitySet.$Lang -Status "ERROR" -Message $LabMsg.NotFound.$Lang -Messages $Msg
    }

    # ========================================================
    # 5-6. VIRTUAL MACHINES
    # ========================================================

    try { $allVMs = @(Get-AzVM -ResourceGroupName $rgName -ErrorAction Stop) } catch { $allVMs = @() }

    $expectedVm1 = if ($prefix) { "$prefix-VM-001" } else { $null }
    $expectedVm2 = if ($prefix) { "$prefix-VM-002" } else { $null }

    $vm1 = if ($expectedVm1) { $allVMs | Where-Object Name -EQ $expectedVm1 | Select-Object -First 1 } else { (Find-PatternMatch -Items $allVMs -Property "Name" -Pattern $LocCfg.VirtualMachines.VM1Pattern).First }
    $vm2 = if ($expectedVm2) { $allVMs | Where-Object Name -EQ $expectedVm2 | Select-Object -First 1 } else { (Find-PatternMatch -Items $allVMs -Property "Name" -Pattern $LocCfg.VirtualMachines.VM2Pattern).First }

    foreach ($vmData in @(
        @{ VM = $vm1; Label = $Check.VM1.$Lang },
        @{ VM = $vm2; Label = $Check.VM2.$Lang }
    )) {
        $vm = $vmData.VM

        if (-not $vm) {
            Add-LabResult -Results ([ref]$results) -Name $vmData.Label -Status "ERROR" -Message $LabMsg.NotFound.$Lang -Messages $Msg
            continue
        }

        $nic = Get-VMNic $vm
        $privateIp = if ($nic -and $nic.IpConfigurations.Count -gt 0) { $nic.IpConfigurations[0].PrivateIpAddress } else { "-" }
        $subnetOk = $nic -and $nic.IpConfigurations.Count -gt 0 -and $webSubnet -and $nic.IpConfigurations[0].Subnet.Id -eq $webSubnet.Id
        $avSetOk = $avSet -and $vm.AvailabilitySetReference -and $vm.AvailabilitySetReference.Id -eq $avSet.Id

        if (-not $subnetOk) {
            Add-LabResult -Results ([ref]$results) -Name $vmData.Label -Status "ERROR" -Message $LabMsg.WrongVmNetwork.$Lang -Messages $Msg
        } elseif (-not $avSetOk) {
            Add-LabResult -Results ([ref]$results) -Name $vmData.Label -Status "ERROR" -Message $LabMsg.WrongVmAvailabilitySet.$Lang -Messages $Msg
        } else {
            Add-LabResult -Results ([ref]$results) -Name $vmData.Label -Status "OK" -Message "$($vm.Name); IP $privateIp" -Messages $Msg
        }
    }

    # ========================================================
    # 7-9. LOAD BALANCER
    # ========================================================

    try {
        $allLbs = @(Get-AzLoadBalancer -ResourceGroupName $rgName -ErrorAction Stop)
        $expectedLbName = if ($prefix) { "$prefix-NLB" } else { $null }

        if ($expectedLbName) {
            $lb = $allLbs | Where-Object Name -EQ $expectedLbName | Select-Object -First 1
        } else {
            $lb = (Find-PatternMatch -Items $allLbs -Property "Name" -Pattern $LocCfg.LoadBalancer.NamePattern).First
        }
    } catch {
        $lb = $null
    }

    if ($lb) {
        $skuOk = $lb.Sku.Name -eq $LocCfg.LoadBalancer.Sku
        Add-LabResult -Results ([ref]$results) -Name $Check.LoadBalancer.$Lang -Status $(if ($skuOk) { "OK" } else { "WARNING" }) -Message $(if ($skuOk) { "$($lb.Name); $($lb.Sku.Name)" } else { "$($LabMsg.WrongLoadBalancer.$Lang); SKU $($lb.Sku.Name)" }) -Messages $Msg

        $frontend = $lb.FrontendIpConfigurations | Where-Object Name -EQ $LocCfg.LoadBalancer.Frontend.Name | Select-Object -First 1
        $backendPool = $lb.BackendAddressPools | Where-Object Name -EQ $LocCfg.LoadBalancer.BackendPool.Name | Select-Object -First 1
        $probe = $lb.Probes | Where-Object Name -EQ $LocCfg.LoadBalancer.Probe.Name | Select-Object -First 1
        $rule = $lb.LoadBalancingRules | Where-Object Name -EQ $LocCfg.LoadBalancer.Rule.Name | Select-Object -First 1

        $probeOk = $probe -and $probe.Protocol -ieq $LocCfg.LoadBalancer.Probe.Protocol -and $probe.Port -eq $LocCfg.LoadBalancer.Probe.Port
        $ruleOk = $rule -and $rule.Protocol -ieq $LocCfg.LoadBalancer.Rule.Protocol -and $rule.FrontendPort -eq $LocCfg.LoadBalancer.Rule.FrontendPort -and $rule.BackendPort -eq $LocCfg.LoadBalancer.Rule.BackendPort -and $frontend -and $backendPool -and $probe -and $rule.FrontendIpConfiguration.Id -eq $frontend.Id -and $rule.BackendAddressPool.Id -eq $backendPool.Id -and $rule.Probe.Id -eq $probe.Id

        $pipOk = $false
        if ($frontend -and $frontend.PublicIpAddress.Id) {
            $pipName = ($frontend.PublicIpAddress.Id -split '/')[-1]
            $pipOk = $pipName -match $LocCfg.LoadBalancer.PublicIPPattern
        }

        if (-not $frontend -or -not $backendPool -or -not $pipOk) {
            Add-LabResult -Results ([ref]$results) -Name $Check.LoadBalancerConfig.$Lang -Status "ERROR" -Message $LabMsg.WrongLoadBalancer.$Lang -Messages $Msg
        } elseif (-not $probeOk) {
            Add-LabResult -Results ([ref]$results) -Name $Check.LoadBalancerConfig.$Lang -Status "ERROR" -Message $LabMsg.WrongProbe.$Lang -Messages $Msg
        } elseif (-not $ruleOk) {
            Add-LabResult -Results ([ref]$results) -Name $Check.LoadBalancerConfig.$Lang -Status "ERROR" -Message $LabMsg.WrongRule.$Lang -Messages $Msg
        } else {
            Add-LabResult -Results ([ref]$results) -Name $Check.LoadBalancerConfig.$Lang -Status "OK" -Message "NLBFrontEnd; TCP 80 -> 80; WebHealthProbe" -Messages $Msg
        }

        $nic1 = Get-VMNic $vm1
        $nic2 = Get-VMNic $vm2
        $nic1InPool = $false
        $nic2InPool = $false

        if ($backendPool) {
            if ($nic1) {
                foreach ($ipConfig in $nic1.IpConfigurations) {
                    if ($ipConfig.LoadBalancerBackendAddressPools.Id -contains $backendPool.Id) { $nic1InPool = $true }
                }
            }

            if ($nic2) {
                foreach ($ipConfig in $nic2.IpConfigurations) {
                    if ($ipConfig.LoadBalancerBackendAddressPools.Id -contains $backendPool.Id) { $nic2InPool = $true }
                }
            }
        }

        if ($nic1InPool -and $nic2InPool) {
            Add-LabResult -Results ([ref]$results) -Name $Check.BackendPool.$Lang -Status "OK" -Message "WEBServerPool; VM-001 + VM-002" -Messages $Msg
        } else {
            Add-LabResult -Results ([ref]$results) -Name $Check.BackendPool.$Lang -Status "ERROR" -Message $LabMsg.WrongBackendPool.$Lang -Messages $Msg
        }
    } else {
        Add-LabResult -Results ([ref]$results) -Name $Check.LoadBalancer.$Lang -Status "ERROR" -Message $LabMsg.NotFound.$Lang -Messages $Msg
        Add-LabResult -Results ([ref]$results) -Name $Check.LoadBalancerConfig.$Lang -Status "ERROR" -Message "Load Balancer" -Messages $Msg
        Add-LabResult -Results ([ref]$results) -Name $Check.BackendPool.$Lang -Status "ERROR" -Message "Load Balancer" -Messages $Msg
    }

    # ========================================================
    # 10. TAGS
    # ========================================================

    $vm1TagsOk = $vm1 -and (Test-TagValue $vm1.Tags "Environment" $LocCfg.Tags.VirtualMachines.Environment) -and (Test-TagValue $vm1.Tags "CreatedBy" "") -and (Test-TagValue $vm1.Tags "NLB" "")
    $vm2TagsOk = $vm2 -and (Test-TagValue $vm2.Tags "Environment" $LocCfg.Tags.VirtualMachines.Environment) -and (Test-TagValue $vm2.Tags "CreatedBy" "") -and (Test-TagValue $vm2.Tags "NLB" "")
    $vnetResource = if ($vnet) { Get-AzResource -ResourceId $vnet.Id -ErrorAction SilentlyContinue } else { $null }
    $vnetTagsOk = $vnetResource -and (Test-TagValue $vnetResource.Tags "Lab" $LocCfg.Tags.VNet.Lab) -and (Test-TagValue $vnetResource.Tags "Environment" $LocCfg.Tags.VNet.Environment)

    if ($vm1TagsOk -and $vm2TagsOk -and $vnetTagsOk) {
        Add-LabResult -Results ([ref]$results) -Name $Check.Tags.$Lang -Status "OK" -Message "VM-001, VM-002, VNet" -Messages $Msg
    } else {
        Add-LabResult -Results ([ref]$results) -Name $Check.Tags.$Lang -Status "WARNING" -Message $LabMsg.TagsMissing.$Lang -Messages $Msg
    }
}

# ============================================================
# GALUTINIS REZULTATAS
# ============================================================

Show-LabResults -Setup $Setup -LabName $LabName -Results $results -LabelWidth 34
