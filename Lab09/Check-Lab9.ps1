<#
.SYNOPSIS
    LAB 09/10 Patikrinimo Scriptas (Hybrid Version v4.0)
.DESCRIPTION
    Tikrina: ACR, VM, Portus.
    ACI tikrinimui naudoja ir PowerShell, ir Azure CLI (backup), kad garantuotų sąrašą.
#>

$ScriptVersion = "LAB 09/10 Check: Hybrid & Robust"
Clear-Host
Write-Host "--- $ScriptVersion ---" -ForegroundColor Cyan

# --- 1. RESURSŲ GRUPĖ ---
$labRG = Get-AzResourceGroup | Where-Object { $_.ResourceGroupName -match "RG-LAB09" } | Select-Object -First 1

if (-not $labRG) {
    Write-Host "[KLAIDA] Nerasta resursų grupė 'RG-LAB09...'" -ForegroundColor Red; exit
}
Write-Host "[OK] Rasta grupė: $($labRG.ResourceGroupName)" -ForegroundColor Green

# --- 2. AZURE CONTAINER REGISTRY (ACR) ---
Write-Host "`n--- 1. Container Registry (ACR) ---" -ForegroundColor Cyan
$acr = Get-AzContainerRegistry -ResourceGroupName $labRG.ResourceGroupName -ErrorAction SilentlyContinue | Select-Object -First 1

if ($acr) {
    Write-Host "[OK] Registras rastas: $($acr.Name)" -ForegroundColor Green
    try {
        $repos = az acr repository list --name $acr.Name --output tsv 2>$null
        if ($repos) {
             $customImages = $repos | Where-Object { $_ -notmatch "hello-world" -and $_ -notmatch "aci-helloworld" }
             if ($customImages) {
                 Write-Host "[OK] Jūsų sukurtas vaizdas rastas registre: $customImages" -ForegroundColor Green
             } else {
                 Write-Host "[INFO] Registre rastas tik 'hello-world' vaizdas." -ForegroundColor Yellow
             }
        }
    } catch { Write-Host "[INFO] Nepavyko nuskaityti vaizdų sąrašo." -ForegroundColor Gray }
} else {
    Write-Host "[KLAIDA] Nerastas ACR" -ForegroundColor Red
}

# --- 3. VIRTUALI MAŠINA (VM) ---
Write-Host "`n--- 2. Linux VM ir Portai ---" -ForegroundColor Cyan
$vm = Get-AzVM -ResourceGroupName $labRG.ResourceGroupName -Name "DockerVM" -ErrorAction SilentlyContinue

if ($vm) {
    Write-Host "[OK] Virtuali mašina 'DockerVM' rasta." -ForegroundColor Green
    $nsg = Get-AzNetworkSecurityGroup -ResourceGroupName $labRG.ResourceGroupName | Select-Object -First 1
    if ($nsg) {
        if ($nsg.SecurityRules | Where-Object { $_.DestinationPortRange -contains "80" -and $_.Access -eq "Allow" }) {
            Write-Host "[OK] Portas 80 (Web) atidarytas." -ForegroundColor Green
        } else { Write-Host "[TRŪKSTA] Portas 80 neatidarytas." -ForegroundColor Red }

        if ($nsg.SecurityRules | Where-Object { $_.DestinationPortRange -contains "9000" -and $_.Access -eq "Allow" }) {
            Write-Host "[OK] Portas 9000 (Portainer) atidarytas." -ForegroundColor Green
        } else { Write-Host "[TRŪKSTA] Portas 9000 neatidarytas." -ForegroundColor Yellow }
    }
} else {
    Write-Host "[TRŪKSTA] Nerasta VM 'DockerVM'." -ForegroundColor Red
}

# --- 4. ACI (Svetainė) - HYBRID CHECK ---
Write-Host "`n--- 3. Container Instance (Svetainė) ---" -ForegroundColor Cyan
$aci = Get-AzContainerGroup -ResourceGroupName $labRG.ResourceGroupName -ErrorAction SilentlyContinue | Select-Object -First 1

if ($aci) {
    if ($aci.ProvisioningState -eq "Succeeded" -or $aci.ProvisioningState -eq "Running") {
         Write-Host "[OK] Konteinerių grupė veikia." -ForegroundColor Green
         if ($aci.IpAddress.Fqdn) {
             Write-Host "     Adresas: http://$($aci.IpAddress.Fqdn)" -ForegroundColor Cyan
         }
         
         Write-Host "`n     --- Konteinerių sąrašas: ---" -ForegroundColor Gray
         
         # 1 BŪDAS: Bandome per PowerShell objektą
         $containersList = $aci.Containers
         
         # 2 BŪDAS (Fallback): Jei PowerShell tuščias, naudojame Azure CLI
         if (-not $containersList) {
             # Write-Host "     [DEBUG] PowerShell objektas tuščias, bandome CLI..." -ForegroundColor DarkGray
             try {
                 $jsonInfo = az container show --resource-group $labRG.ResourceGroupName --name $aci.Name --output json | ConvertFrom-Json
                 $containersList = $jsonInfo.containers
             } catch {}
         }

         # SĄRAŠO SPAUSDINIMAS
         if ($containersList) {
             foreach ($container in $containersList) {
                 # CLI ir PS objektų struktūros gali skirtis, normalizuojame
                 $imgName = if ($container.image) { $container.image } else { $container.Image }
                 $contName = if ($container.name) { $container.name } else { $container.Name }
                 
                 if ($imgName -match "azurecr.io") {
                     Write-Host "     [+] $contName : $imgName (Jūsų Privatus)" -ForegroundColor Green
                 } else {
                     Write-Host "     [-] $contName : $imgName (Viešas/Default)" -ForegroundColor Yellow
                 }
             }
         } else {
             Write-Host "     [KLAIDA] Nepavyko nuskaityti sąrašo nei per PS, nei per CLI." -ForegroundColor Red
         }

    } else {
         Write-Host "[KLAIDA] Statusas: $($aci.ProvisioningState)" -ForegroundColor Red
    }
} else {
    Write-Host "[KLAIDA] Nerastas ACI konteineris." -ForegroundColor Red
}

Write-Host "`n--- TIKRINIMAS BAIGTAS ---" -ForegroundColor Cyan
