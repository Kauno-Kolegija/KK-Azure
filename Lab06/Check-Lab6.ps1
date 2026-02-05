<#
.SYNOPSIS
    LAB 09/10 Patikrinimo Scriptas (Student Version v3.0)
.DESCRIPTION
    Tikrina: ACR, Linux VM, Portus ir ACI.
    Apsaugotas nuo 'Null Array' klaidų.
#>

$ScriptVersion = "LAB 09/10 Check: Docker & Cloud"
Clear-Host
Write-Host "--- $ScriptVersion ---" -ForegroundColor Cyan

# --- 1. RESURSŲ GRUPĖ ---
$labRG = Get-AzResourceGroup | Where-Object { $_.ResourceGroupName -match "RG-LAB09" } | Select-Object -First 1

if (-not $labRG) {
    Write-Host "[KLAIDA] Nerasta resursų grupė, prasidedanti 'RG-LAB09...'" -ForegroundColor Red
    exit
}
Write-Host "[OK] Rasta grupė: $($labRG.ResourceGroupName)" -ForegroundColor Green

# --- 2. AZURE CONTAINER REGISTRY (ACR) ---
Write-Host "`n--- 1. Container Registry (ACR) ---" -ForegroundColor Cyan
$acr = Get-AzContainerRegistry -ResourceGroupName $labRG.ResourceGroupName -ErrorAction SilentlyContinue | Select-Object -First 1

if ($acr) {
    Write-Host "[OK] Registras rastas: $($acr.Name)" -ForegroundColor Green
    
    # Tikriname, ar yra įkeltų vaizdų
    try {
        $repos = az acr repository list --name $acr.Name --output tsv 2>$null
        if ($repos) {
             # Ieškome studento sukurto vaizdo (filtruojame hello-world)
             $customImages = $repos | Where-Object { $_ -notmatch "hello-world" -and $_ -notmatch "aci-helloworld" }
             
             if ($customImages) {
                 Write-Host "[OK] Jūsų sukurtas vaizdas rastas registre: $customImages" -ForegroundColor Green
             } else {
                 Write-Host "[INFO] Registre rastas tik 'hello-world' vaizdas." -ForegroundColor Yellow
             }
        }
    } catch {
        Write-Host "[INFO] Nepavyko nuskaityti vaizdų sąrašo." -ForegroundColor Gray
    }
} else {
    Write-Host "[KLAIDA] Nerastas Container Registry (ACR)" -ForegroundColor Red
}

# --- 3. VIRTUALI MAŠINA (VM) ---
Write-Host "`n--- 2. Linux VM ir Portai ---" -ForegroundColor Cyan
$vm = Get-AzVM -ResourceGroupName $labRG.ResourceGroupName -Name "DockerVM" -ErrorAction SilentlyContinue

if ($vm) {
    Write-Host "[OK] Virtuali mašina 'DockerVM' rasta." -ForegroundColor Green
    
    # Tikriname NSG (Saugumo taisykles)
    $nsg = Get-AzNetworkSecurityGroup -ResourceGroupName $labRG.ResourceGroupName | Select-Object -First 1
    if ($nsg) {
        $rules = $nsg.SecurityRules
        
        # 80 Portas
        if ($rules | Where-Object { $_.DestinationPortRange -contains "80" -and $_.Access -eq "Allow" }) {
            Write-Host "[OK] Portas 80 (Web) atidarytas." -ForegroundColor Green
        } else {
            Write-Host "[TRŪKSTA] Portas 80 neatidarytas." -ForegroundColor Red
        }

        # 9000 Portas
        if ($rules | Where-Object { $_.DestinationPortRange -contains "9000" -and $_.Access -eq "Allow" }) {
            Write-Host "[OK] Portas 9000 (Portainer) atidarytas." -ForegroundColor Green
        } else {
            Write-Host "[TRŪKSTA] Portas 9000 neatidarytas." -ForegroundColor Yellow
        }
    }
} else {
    Write-Host "[TRŪKSTA] Nerasta VM su pavadinimu 'DockerVM'." -ForegroundColor Red
}

# --- 4. ACI (Svetainė) ---
Write-Host "`n--- 3. Container Instance (Svetainė) ---" -ForegroundColor Cyan
$aci = Get-AzContainerGroup -ResourceGroupName $labRG.ResourceGroupName -ErrorAction SilentlyContinue | Select-Object -First 1

if ($aci) {
    # Būsenos tikrinimas
    if ($aci.ProvisioningState -eq "Succeeded" -or $aci.ProvisioningState -eq "Running") {
         Write-Host "[OK] Konteineris veikia." -ForegroundColor Green
         if ($aci.IpAddress.Fqdn) {
             Write-Host "     Adresas: http://$($aci.IpAddress.Fqdn)" -ForegroundColor Cyan
         }
         
         # --- SAUGUS VAIZDO TIKRINIMAS (BE KLAIDŲ) ---
         $imageSource = "Unknown/Public"
         $isPrivate = $false

         # 1 Būdas: Bandome skaityti Containers masyvą (jei jis ne tuščias)
         if ($aci.Containers -and $aci.Containers.Count -gt 0) {
             $imageSource = $aci.Containers[0].Image
             if ($imageSource -match "azurecr.io") { $isPrivate = $true }
         } 
         # 2 Būdas: Tikriname ImageRegistryCredentials (jei masyvas tuščias, bet yra slaptažodžiai)
         elseif ($aci.ImageRegistryCredentials -and $aci.ImageRegistryCredentials.Count -gt 0) {
             $isPrivate = $true
             $imageSource = "Private Registry Image"
         }

         # Rezultato spausdinimas
         if ($isPrivate) {
             Write-Host "[PUIKU] Naudojamas jūsų unikalus vaizdas ($imageSource)." -ForegroundColor Green
         } else {
             Write-Host "[PASTABA] Naudojamas viešas 'Hello World' vaizdas." -ForegroundColor Yellow
             Write-Host "          (Tai tinka įskaitai, bet 10 balų vertas darbas naudotų 'mantas-web' vaizdą)." -ForegroundColor Gray
         }

    } else {
         Write-Host "[KLAIDA] Konteineris bando pasileisti, bet statusas: $($aci.ProvisioningState)" -ForegroundColor Red
    }
} else {
    Write-Host "[KLAIDA] Nerastas veikiantis ACI konteineris." -ForegroundColor Red
}

Write-Host "`n--- TIKRINIMAS BAIGTAS ---" -ForegroundColor Cyan