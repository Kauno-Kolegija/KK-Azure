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

# --- Kalba ---
if ($Lang -notin @("LT", "EN")) { $Lang = "LT" }

# --- Inicializacija ---
$Setup = Initialize-Lab `
    -LocalConfigUrl "https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/Lab05/Check-Lab5-config.json" `
    -Lang $Lang

$LocCfg  = $Setup.LocalConfig
$Check   = $LocCfg.Checks
$LabMsg  = $LocCfg.Messages
$Msg     = $Setup.Messages
$LabName = $LocCfg.LabName.$Lang

$OkStatus      = $Msg.Ok
$ErrorStatus   = $Msg.Error
$MissingStatus = $LabMsg.Missing.$Lang
$WarningStatus = $LabMsg.Warning.$Lang

$results = @()

function Add-Result {
    param(
        [string]$Name,
        [string]$Text,
        [string]$Color = "White"
    )

    $script:results += [PSCustomObject]@{
        Name  = $Name
        Text  = $Text
        Color = $Color
    }
}

function Test-PortRule {
    param(
        $Rule,
        [string]$Protocol,
        [string]$Port,
        [string]$Access
    )

    if (-not $Rule) { return $false }

    $ports = @()
    if ($Rule.DestinationPortRange)  { $ports += $Rule.DestinationPortRange }
    if ($Rule.DestinationPortRanges) { $ports += $Rule.DestinationPortRanges }

    return (
        $Rule.Protocol -ieq $Protocol -and
        $Rule.Access -ieq $Access -and
        $ports -contains $Port
    )
}

function Get-VMNic {
    param($VM)

    if (-not $VM -or -not $VM.NetworkProfile.NetworkInterfaces) {
        return $null
    }

    $nicId = $VM.NetworkProfile.NetworkInterfaces[0].Id
    if (-not $nicId) { return $null }

    $nicName = ($nicId -split '/')[-1]

    try {
        return Get-AzNetworkInterface `
            -ResourceGroupName $VM.ResourceGroupName `
            -Name $nicName `
            -ErrorAction Stop
    } catch {
        return $null
    }
}

function Test-TagValue {
    param(
        $Tags,
        [string]$Name,
        [string]$ExpectedValue
    )

    if (-not $Tags -or -not $Tags.ContainsKey($Name)) {
        return $false
    }

    if ($ExpectedValue) {
        return $Tags[$Name] -eq $ExpectedValue
    }

    return -not [string]::IsNullOrWhiteSpace([string]$Tags[$Name])
}

# ============================================================
# 1. RESOURCE GROUP
# ============================================================

$targetRG = Get-AzResourceGroup |
    Where-Object ResourceGroupName -Match $LocCfg.ResourceGroup.Pattern |
    Select-Object -First 1

if ($targetRG) {
    Add-Result $Check.ResourceGroup.$Lang `
        "[$OkStatus] - $($targetRG.ResourceGroupName) ($($targetRG.Location))" `
        "Green"
} else {
    Add-Result $Check.ResourceGroup.$Lang `
        "[$ErrorStatus] - $($LabMsg.NotFound.$Lang)" `
        "Red"
}

# Toliau tikriname tik jei RG egzistuoja
if ($targetRG) {

    $rgName = $targetRG.ResourceGroupName

    # ========================================================
    # 2. VNET + WEBSUBNET
    # ========================================================

    $vnet = Get-AzVirtualNetwork -ResourceGroupName $rgName |
        Where-Object Name -Match $LocCfg.Network.VNetPattern |
        Select-Object -First 1

    if ($vnet) {

        $prefix = $vnet.Name -replace '-VNet$', ''

        $addressOk = $vnet.AddressSpace.AddressPrefixes -contains $LocCfg.Network.AddressSpace

        $webSubnet = $vnet.Subnets |
            Where-Object Name -EQ $LocCfg.Network.Subnet.Name |
            Select-Object -First 1

        $subnetOk = $webSubnet -and (
            $webSubnet.AddressPrefix -eq $LocCfg.Network.Subnet.Prefix -or
            $webSubnet.AddressPrefixes -contains $LocCfg.Network.Subnet.Prefix
        )

        $vnetInfo = "$($vnet.Name) - $($vnet.AddressSpace.AddressPrefixes -join ', ')"

        if ($webSubnet) {
            $subnetPrefix = if ($webSubnet.AddressPrefix) {
                $webSubnet.AddressPrefix
            } else {
                $webSubnet.AddressPrefixes -join ", "
            }

            $vnetInfo += "; WebSubnet $subnetPrefix"
        }

        if ($addressOk -and $subnetOk) {
            Add-Result $Check.VNet.$Lang "[$OkStatus] - $vnetInfo" "Green"
        }
        elseif (-not $addressOk) {
            Add-Result $Check.VNet.$Lang `
                "[$ErrorStatus] - $($LabMsg.WrongAddressSpace.$Lang); $vnetInfo" `
                "Red"
        }
        else {
            Add-Result $Check.VNet.$Lang `
                "[$ErrorStatus] - $($LabMsg.WrongSubnet.$Lang); $vnetInfo" `
                "Red"
        }

    } else {
        $prefix = $null
        $webSubnet = $null

        Add-Result $Check.VNet.$Lang `
            "[$MissingStatus] - $($LabMsg.NotFound.$Lang)" `
            "Red"
    }

    # ========================================================
    # 3. NSG + RULES
    # ========================================================

    $expectedNsgName = if ($prefix) { "$prefix-NSG" } else { $null }

    $nsg = if ($expectedNsgName) {
        Get-AzNetworkSecurityGroup -ResourceGroupName $rgName |
            Where-Object Name -EQ $expectedNsgName |
            Select-Object -First 1
    } else {
        Get-AzNetworkSecurityGroup -ResourceGroupName $rgName |
            Where-Object Name -Match $LocCfg.NSG.NamePattern |
            Select-Object -First 1
    }

    if ($nsg) {

        $webRule = $nsg.SecurityRules |
            Where-Object Name -EQ $LocCfg.NSG.WebRule.Name |
            Select-Object -First 1

        $rdpRule = $nsg.SecurityRules |
            Where-Object Name -EQ $LocCfg.NSG.RdpRule.Name |
            Select-Object -First 1

        $webRuleOk = Test-PortRule `
            $webRule `
            $LocCfg.NSG.WebRule.Protocol `
            $LocCfg.NSG.WebRule.DestinationPort `
            $LocCfg.NSG.WebRule.Access

        $rdpRuleOk = Test-PortRule `
            $rdpRule `
            $LocCfg.NSG.RdpRule.Protocol `
            $LocCfg.NSG.RdpRule.DestinationPort `
            $LocCfg.NSG.RdpRule.Access

        $priorityOk = $false

        if ($webRule -and $rdpRule) {
            $priorityOk = (
                $webRule.Priority -ne $rdpRule.Priority -and
                $webRule.Priority -ge $LocCfg.NSG.Priority.Minimum -and
                $webRule.Priority -le $LocCfg.NSG.Priority.Maximum -and
                $rdpRule.Priority -ge $LocCfg.NSG.Priority.Minimum -and
                $rdpRule.Priority -le $LocCfg.NSG.Priority.Maximum
            )
        }

        $nsgAssociated = $false

        if ($webSubnet -and $webSubnet.NetworkSecurityGroup.Id) {
            $nsgAssociated = $webSubnet.NetworkSecurityGroup.Id -eq $nsg.Id
        }

        $nsgInfo = "$($nsg.Name); WEB:$($webRule.Priority); RDP:$($rdpRule.Priority)"

        if (-not $nsgAssociated) {
            Add-Result $Check.NSG.$Lang `
                "[$ErrorStatus] - $($LabMsg.NsgNotAssociated.$Lang)" `
                "Red"
        }
        elseif (-not $webRuleOk -or -not $rdpRuleOk) {
            Add-Result $Check.NSG.$Lang `
                "[$ErrorStatus] - $($LabMsg.WrongNsgRules.$Lang)" `
                "Red"
        }
        elseif (-not $priorityOk) {
            Add-Result $Check.NSG.$Lang `
                "[$ErrorStatus] - $($LabMsg.DuplicatePriority.$Lang)" `
                "Red"
        }
        else {
            Add-Result $Check.NSG.$Lang "[$OkStatus] - $nsgInfo" "Green"
        }

    } else {
        Add-Result $Check.NSG.$Lang `
            "[$MissingStatus] - $($LabMsg.NotFound.$Lang)" `
            "Red"
    }

    # ========================================================
    # 4. AVAILABILITY SET
    # ========================================================

    $expectedAvSetName = if ($prefix) { "$prefix-AvailabilitySet" } else { $null }

    $avSet = if ($expectedAvSetName) {
        Get-AzAvailabilitySet -ResourceGroupName $rgName |
            Where-Object Name -EQ $expectedAvSetName |
            Select-Object -First 1
    } else {
        Get-AzAvailabilitySet -ResourceGroupName $rgName |
            Where-Object Name -Match $LocCfg.AvailabilitySet.NamePattern |
            Select-Object -First 1
    }

    if ($avSet) {

        $avSetOk = (
            $avSet.PlatformFaultDomainCount -eq $LocCfg.AvailabilitySet.FaultDomains -and
            $avSet.PlatformUpdateDomainCount -eq $LocCfg.AvailabilitySet.UpdateDomains
        )

        $avInfo = "$($avSet.Name); FD=$($avSet.PlatformFaultDomainCount); UD=$($avSet.PlatformUpdateDomainCount)"

        if ($avSetOk) {
            Add-Result $Check.AvailabilitySet.$Lang "[$OkStatus] - $avInfo" "Green"
        } else {
            Add-Result $Check.AvailabilitySet.$Lang `
                "[$ErrorStatus] - $($LabMsg.WrongAvailabilitySet.$Lang); $avInfo" `
                "Red"
        }

    } else {
        Add-Result $Check.AvailabilitySet.$Lang `
            "[$MissingStatus] - $($LabMsg.NotFound.$Lang)" `
            "Red"
    }

    # ========================================================
    # 5-6. VIRTUAL MACHINES
    # ========================================================

    $expectedVm1 = if ($prefix) { "$prefix-VM-001" } else { $null }
    $expectedVm2 = if ($prefix) { "$prefix-VM-002" } else { $null }

    $allVMs = Get-AzVM -ResourceGroupName $rgName

    $vm1 = if ($expectedVm1) {
        $allVMs | Where-Object Name -EQ $expectedVm1 | Select-Object -First 1
    } else {
        $allVMs | Where-Object Name -Match $LocCfg.VirtualMachines.VM1Pattern | Select-Object -First 1
    }

    $vm2 = if ($expectedVm2) {
        $allVMs | Where-Object Name -EQ $expectedVm2 | Select-Object -First 1
    } else {
        $allVMs | Where-Object Name -Match $LocCfg.VirtualMachines.VM2Pattern | Select-Object -First 1
    }

    foreach ($vmData in @(
        @{ VM = $vm1; Label = $Check.VM1.$Lang },
        @{ VM = $vm2; Label = $Check.VM2.$Lang }
    )) {

        $vm = $vmData.VM

        if (-not $vm) {
            Add-Result $vmData.Label `
                "[$MissingStatus] - $($LabMsg.NotFound.$Lang)" `
                "Red"

            continue
        }

        $nic = Get-VMNic $vm

        $subnetOk = $false
        $privateIp = "-"

        if ($nic -and $nic.IpConfigurations.Count -gt 0) {

            $ipConfig = $nic.IpConfigurations[0]
            $privateIp = $ipConfig.PrivateIpAddress

            if ($ipConfig.Subnet.Id) {
                $subnetName = ($ipConfig.Subnet.Id -split '/')[-1]
                $subnetOk = $subnetName -eq $LocCfg.Network.Subnet.Name
            }
        }

        $avSetOk = (
            $avSet -and
            $vm.AvailabilitySetReference -and
            $vm.AvailabilitySetReference.Id -eq $avSet.Id
        )

        if (-not $subnetOk) {
            Add-Result $vmData.Label `
                "[$ErrorStatus] - $($LabMsg.WrongVmNetwork.$Lang)" `
                "Red"
        }
        elseif (-not $avSetOk) {
            Add-Result $vmData.Label `
                "[$ErrorStatus] - $($LabMsg.WrongVmAvailabilitySet.$Lang)" `
                "Red"
        }
        else {
            Add-Result $vmData.Label `
                "[$OkStatus] - $($vm.Name); IP $privateIp" `
                "Green"
        }
    }

    # ========================================================
    # 7. LOAD BALANCER
    # ========================================================

    $expectedLbName = if ($prefix) { "$prefix-NLB" } else { $null }

    $lb = if ($expectedLbName) {
        Get-AzLoadBalancer -ResourceGroupName $rgName |
            Where-Object Name -EQ $expectedLbName |
            Select-Object -First 1
    } else {
        Get-AzLoadBalancer -ResourceGroupName $rgName |
            Where-Object Name -Match $LocCfg.LoadBalancer.NamePattern |
            Select-Object -First 1
    }

    if ($lb) {

        $skuOk = $lb.Sku.Name -eq $LocCfg.LoadBalancer.Sku

        if ($skuOk) {
            Add-Result $Check.LoadBalancer.$Lang `
                "[$OkStatus] - $($lb.Name); $($lb.Sku.Name)" `
                "Green"
        } else {
            Add-Result $Check.LoadBalancer.$Lang `
                "[$ErrorStatus] - $($LabMsg.WrongLoadBalancer.$Lang); SKU $($lb.Sku.Name)" `
                "Red"
        }

        # ====================================================
        # 8. LOAD BALANCER CONFIG
        # ====================================================

        $frontend = $lb.FrontendIpConfigurations |
            Where-Object Name -EQ $LocCfg.LoadBalancer.Frontend.Name |
            Select-Object -First 1

        $backendPool = $lb.BackendAddressPools |
            Where-Object Name -EQ $LocCfg.LoadBalancer.BackendPool.Name |
            Select-Object -First 1

        $probe = $lb.Probes |
            Where-Object Name -EQ $LocCfg.LoadBalancer.Probe.Name |
            Select-Object -First 1

        $rule = $lb.LoadBalancingRules |
            Where-Object Name -EQ $LocCfg.LoadBalancer.Rule.Name |
            Select-Object -First 1

        $probeOk = (
            $probe -and
            $probe.Protocol -ieq $LocCfg.LoadBalancer.Probe.Protocol -and
            $probe.Port -eq $LocCfg.LoadBalancer.Probe.Port
        )

        $ruleOk = (
            $rule -and
            $rule.Protocol -ieq $LocCfg.LoadBalancer.Rule.Protocol -and
            $rule.FrontendPort -eq $LocCfg.LoadBalancer.Rule.FrontendPort -and
            $rule.BackendPort -eq $LocCfg.LoadBalancer.Rule.BackendPort -and
            $frontend -and
            $backendPool -and
            $probe -and
            $rule.FrontendIpConfiguration.Id -eq $frontend.Id -and
            $rule.BackendAddressPool.Id -eq $backendPool.Id -and
            $rule.Probe.Id -eq $probe.Id
        )

        $pipOk = $false

        if ($frontend -and $frontend.PublicIpAddress.Id) {
            $pipName = ($frontend.PublicIpAddress.Id -split '/')[-1]
            $pipOk = $pipName -match $LocCfg.LoadBalancer.PublicIPPattern
        }

        if (-not $frontend -or -not $backendPool -or -not $pipOk) {
            Add-Result $Check.LoadBalancerConfig.$Lang `
                "[$ErrorStatus] - $($LabMsg.WrongLoadBalancer.$Lang)" `
                "Red"
        }
        elseif (-not $probeOk) {
            Add-Result $Check.LoadBalancerConfig.$Lang `
                "[$ErrorStatus] - $($LabMsg.WrongProbe.$Lang)" `
                "Red"
        }
        elseif (-not $ruleOk) {
            Add-Result $Check.LoadBalancerConfig.$Lang `
                "[$ErrorStatus] - $($LabMsg.WrongRule.$Lang)" `
                "Red"
        }
        else {
            Add-Result $Check.LoadBalancerConfig.$Lang `
                "[$OkStatus] - NLBFrontEnd; TCP 80 -> 80; WebHealthProbe" `
                "Green"
        }

        # ====================================================
        # 9. BACKEND POOL
        # ====================================================

        $nic1 = Get-VMNic $vm1
        $nic2 = Get-VMNic $vm2

        $nic1InPool = $false
        $nic2InPool = $false

        if ($backendPool) {

            if ($nic1) {
                foreach ($ipConfig in $nic1.IpConfigurations) {
                    if ($ipConfig.LoadBalancerBackendAddressPools.Id -contains $backendPool.Id) {
                        $nic1InPool = $true
                    }
                }
            }

            if ($nic2) {
                foreach ($ipConfig in $nic2.IpConfigurations) {
                    if ($ipConfig.LoadBalancerBackendAddressPools.Id -contains $backendPool.Id) {
                        $nic2InPool = $true
                    }
                }
            }
        }

        if ($nic1InPool -and $nic2InPool) {
            Add-Result $Check.BackendPool.$Lang `
                "[$OkStatus] - WEBServerPool; VM-001 + VM-002" `
                "Green"
        } else {
            Add-Result $Check.BackendPool.$Lang `
                "[$ErrorStatus] - $($LabMsg.WrongBackendPool.$Lang)" `
                "Red"
        }

    } else {

        Add-Result $Check.LoadBalancer.$Lang `
            "[$MissingStatus] - $($LabMsg.NotFound.$Lang)" `
            "Red"

        Add-Result $Check.LoadBalancerConfig.$Lang `
            "[$MissingStatus] - Load Balancer" `
            "Red"

        Add-Result $Check.BackendPool.$Lang `
            "[$MissingStatus] - Load Balancer" `
            "Red"
    }

    # ========================================================
    # 10. TAGS
    # ========================================================

    $vm1TagsOk = (
        $vm1 -and
        (Test-TagValue $vm1.Tags "Environment" $LocCfg.Tags.VirtualMachines.Environment) -and
        (Test-TagValue $vm1.Tags "CreatedBy" "") -and
        (Test-TagValue $vm1.Tags "NLB" "")
    )

    $vm2TagsOk = (
        $vm2 -and
        (Test-TagValue $vm2.Tags "Environment" $LocCfg.Tags.VirtualMachines.Environment) -and
        (Test-TagValue $vm2.Tags "CreatedBy" "") -and
        (Test-TagValue $vm2.Tags "NLB" "")
    )

    $vnetTagsOk = (
        $vnet -and
        (Test-TagValue $vnet.Tags "Lab" $LocCfg.Tags.VNet.Lab) -and
        (Test-TagValue $vnet.Tags "Environment" $LocCfg.Tags.VNet.Environment)
    )

    if ($vm1TagsOk -and $vm2TagsOk -and $vnetTagsOk) {
        Add-Result $Check.Tags.$Lang `
            "[$OkStatus] - VM-001, VM-002, VNet" `
            "Green"
    } else {
        Add-Result $Check.Tags.$Lang `
            "[$ErrorStatus] - $($LabMsg.TagsMissing.$Lang)" `
            "Red"
    }
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

$i = 1

foreach ($res in $results) {

    $label = "$i. $($res.Name):"
    $targetWidth = 34

    $spaces = $targetWidth - $label.Length
    if ($spaces -lt 1) { $spaces = 1 }

    Write-Host "$label$(" " * $spaces)" -NoNewline
    Write-Host $res.Text -ForegroundColor $res.Color

    $i++
}

Write-Host "==================================================" -ForegroundColor Gray
Write-Host ""