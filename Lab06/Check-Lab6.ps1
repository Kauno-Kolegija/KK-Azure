<#
.SYNOPSIS
    LAB 09/10 Patikrinimo Scriptas (Final Version - List All)
.DESCRIPTION
    Tikrina: ACR, Linux VM, Portus ir išvardina visus ACI konteinerius.
#>

$ScriptVersion = "LAB 09/10 Check: Docker & Cloud"
Clear-Host
Write-Host "--- $ScriptVersion ---" -ForegroundColor Cyan

# --- 1. RESURSŲ GRUPĖ ---
$labRG = Get-AzResourceGroup | Where-Object { $_.ResourceGroupName -match "RG-LAB09" } | Select-Object -First 1

if (-not $labRG) {
    Write-Host "[KLAIDA] Nerasta resursų grupė 'RG-LAB09...'" -ForegroundColor Red
    exit
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

# --- 4. ACI (Svetainė) - SĄRAŠO VERSIJA ---
Write-Host "`n--- 3. Container Instance (Svetainė) ---" -ForegroundColor Cyan
$aci = Get-AzContainerGroup -ResourceGroupName $labRG.ResourceGroupName -ErrorAction SilentlyContinue | Select-Object -First 1

if ($aci) {
    if ($aci.ProvisioningState -eq "Succeeded" -or $aci.ProvisioningState -eq "Running") {
         Write-Host "[OK] Konteinerių grupė veikia." -ForegroundColor Green
         if ($aci.IpAddress.Fqdn) {
             Write-Host "     Adresas: http://$($aci.IpAddress.Fqdn)" -ForegroundColor Cyan
         }
         
         Write-Host "`n     --- Konteinerių sąrašas: ---" -ForegroundColor Gray
         
         # CIKLAS PER VISUS KONTEINERIUS
         if ($aci.Containers) {
             foreach ($container in $aci.Containers) {
                 $imgName = $container.Image
                 $contName = $container.Name
                 
                 # Tikriname ar privatus
                 if ($imgName -match "azurecr.io") {
                     Write-Host "     [+] $contName : $imgName (Jūsų Privatus)" -ForegroundColor Green
                 } else {
                     Write-Host "     [-] $contName : $imgName (Viešas/Default)" -ForegroundColor Yellow
                 }
             }
         } else {
             Write-Host "     [INFO] Negalima nuskaityti detalaus sąrašo." -ForegroundColor Gray
         }

    } else {
         Write-Host "[KLAIDA] Statusas: $($aci.ProvisioningState)" -ForegroundColor Red
    }
} else {
    Write-Host "[KLAIDA] Nerastas ACI konteineris." -ForegroundColor Red
}

Write-Host "`n--- TIKRINIMAS BAIGTAS ---" -ForegroundColor Cyan