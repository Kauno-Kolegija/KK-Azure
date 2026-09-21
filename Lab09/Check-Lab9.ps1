if ($PSScriptRoot) {
    . (Join-Path $PSScriptRoot '../configs/common.ps1')
} else {
    Invoke-RestMethod 'https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/configs/common.ps1' -ErrorAction Stop | Invoke-Expression
}
$Setup = Initialize-Lab -ConfigDirectory $PSScriptRoot -LocalConfigUrl 'https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/Lab09/Check-Lab9-config.json'
$LocCfg = $Setup.LocalConfig
<#
.SYNOPSIS
    LAB 09/10 Patikrinimo Scriptas (v6.0 - Compact)
.DESCRIPTION
    Tikrina: ACR (sutrumpintai), VM, Portus, ACI (tik statusą ir URL).
#>

$ScriptVersion = "LAB 09/10 Check: Final Version"
Clear-Host
Write-Host "--- $ScriptVersion ---" -ForegroundColor Cyan

# --- 1. RESURSŲ GRUPĖ ---
$labRG = Get-AzResourceGroup | Where-Object { $_.ResourceGroupName -match $LocCfg.ResourceGroupPattern } | Select-Object -First 1

if (-not $labRG) {
    Write-Host "[KLAIDA] Nerasta resursų grupė 'RG-LAB09...'" -ForegroundColor Red; exit
}
Write-Host "[OK] Rasta grupė: $($labRG.ResourceGroupName)" -ForegroundColor Green

# --- 2. AZURE CONTAINER REGISTRY (ACR) ---
Write-Host "--- 1. Container Registry (ACR) ---" -ForegroundColor Cyan
$acr = Get-AzContainerRegistry -ResourceGroupName $labRG.ResourceGroupName -ErrorAction SilentlyContinue | Select-Object -First 1

if ($acr) {
    Write-Host "[OK] Registras rastas: $($acr.Name)" -ForegroundColor Green
    
    try {
        # Gauname repozitorijas ir iškart spausdiname po registru
        $reposRaw = az acr repository list --name $acr.Name --subscription (Get-AzContext).Subscription.Id --output tsv
        if ($LASTEXITCODE -ne 0) { throw 'Azure CLI nepavyko nuskaityti ACR repozitorijų.' }
        $repos = $reposRaw -split "\s+" | Where-Object { $_ -ne "" }
        
        if ($repos) {
             foreach ($repo in $repos) {
                 if ($repo -match "hello-world" -or $repo -match "aci-helloworld") {
                     Write-Host "     [+] $repo (Microsoft/Demo)" -ForegroundColor Yellow
                 } else {
                     Write-Host "     [+] $repo (Kilmė netikrinta)" -ForegroundColor Gray
                 }
             }
        } else {
             Write-Host "     [INFO] Registras tuščias." -ForegroundColor Yellow
        }
    } catch { Write-Host "[KLAIDA] $($_.Exception.Message)" -ForegroundColor Red }
} else {
    Write-Host "[KLAIDA] Nerastas ACR" -ForegroundColor Red
}

# --- 3. VIRTUALI MAŠINA (VM) ---
Write-Host "--- 2. Linux VM ir Portai ---" -ForegroundColor Cyan
$vm = Get-AzVM -ResourceGroupName $labRG.ResourceGroupName -Name "DockerVM" -ErrorAction SilentlyContinue

if ($vm) {
    if ($vm.StorageProfile.OsDisk.OsType -eq 'Linux') {
        Write-Host "[OK] Linux virtuali mašina 'DockerVM' rasta." -ForegroundColor Green
    } else { Write-Host '[KLAIDA] DockerVM operacinė sistema nėra Linux.' -ForegroundColor Red }
    $nic = Get-AzNetworkInterface -ResourceId $vm.NetworkProfile.NetworkInterfaces[0].Id -ErrorAction Stop
    $subnetParts = $nic.IpConfigurations[0].Subnet.Id -split '/'
    $vnet = Get-AzVirtualNetwork -ResourceGroupName $subnetParts[4] -Name $subnetParts[8] -ErrorAction Stop
    $subnet = $vnet.Subnets | Where-Object { $_.Id -eq $nic.IpConfigurations[0].Subnet.Id }
    $nsgIds = @(@($nic.NetworkSecurityGroup.Id, $subnet.NetworkSecurityGroup.Id) | Where-Object { $_ } | Select-Object -Unique)
    if ($nsgIds.Count -eq 0) { Write-Host '[TRŪKSTA] VM NIC ir potinkliui nepriskirta NSG.' -ForegroundColor Red }
    foreach ($nsgId in $nsgIds) {
        $parts = $nsgId -split '/'
        $nsg = Get-AzNetworkSecurityGroup -ResourceGroupName $parts[4] -Name $parts[-1] -ErrorAction Stop
        foreach ($port in @(80, 9000)) {
            if (Get-LabNsgPortRule -Nsg $nsg -Port $port -Access Allow) {
                Write-Host "[OK] $($nsg.Name): Inbound TCP Allow $port taisyklė (pasiekiamumas netikrintas)." -ForegroundColor Green
            } else {
                Write-Host "[DĖMESIO] $($nsg.Name): TCP $port Allow nepatvirtinta; tikrinkite taisykles ir prioritetus." -ForegroundColor Yellow
            }
        }
    }
} else {
    Write-Host "[TRŪKSTA] Nerasta VM 'DockerVM'." -ForegroundColor Red
}

# --- 4. ACI (Svetainė) ---
Write-Host "--- 3. Container Instance (Svetainė) ---" -ForegroundColor Cyan
$aci = Get-AzContainerGroup -ResourceGroupName $labRG.ResourceGroupName -ErrorAction SilentlyContinue | Select-Object -First 1

if ($aci) {
    if ($aci.ProvisioningState -eq "Succeeded") {
         Write-Host "[OK] Konteinerių grupė sukurta (programos veikimas netikrintas)." -ForegroundColor Green
         if ($aci.IpAddress.Fqdn) {
             Write-Host "     Adresas: http://$($aci.IpAddress.Fqdn)" -ForegroundColor Cyan
         }
         # Konteinerių sąrašas pašalintas, kad būtų švariau
    } else {
         Write-Host "[KLAIDA] Statusas: $($aci.ProvisioningState)" -ForegroundColor Red
    }
} else {
    Write-Host "[KLAIDA] Nerastas ACI konteineris." -ForegroundColor Red
}

Write-Host "--- TIKRINIMAS BAIGTAS ---" -ForegroundColor Cyan
