# --- LAB 09 TIKRINIMAS: Docker, ACI & VM ---
# Versija: 2.0 (Full DevOps Cycle)

$ScriptVersion = "LAB 09 Check: Containers & Infrastructure"
Clear-Host
Write-Host "--- $ScriptVersion ---" -ForegroundColor Cyan

# 1. Ieškome Resursų Grupės (pagal šabloną RG-LAB09*)
$labRG = Get-AzResourceGroup | Where-Object { $_.ResourceGroupName -match "RG-LAB09" } | Select-Object -First 1

if (-not $labRG) {
    Write-Host "[KLAIDA] Nerasta jokia resursų grupė, prasidedanti 'RG-LAB09...'" -ForegroundColor Red
    Write-Host "         Patikrinkite, ar sukūrėte grupę teisingu pavadinimu."
    exit
}
Write-Host "[OK] Rasta grupė: $($labRG.ResourceGroupName)" -ForegroundColor Green

# ---------------------------------------------------------
# 2. Azure Container Registry (ACR) Tikrinimas
# ---------------------------------------------------------
Write-Host "`n--- 1. Container Registry (ACR) ---" -ForegroundColor Cyan
$acr = Get-AzContainerRegistry -ResourceGroupName $labRG.ResourceGroupName -ErrorAction SilentlyContinue | Select-Object -First 1

if ($acr) {
    Write-Host "[OK] Registras rastas: $($acr.Name)" -ForegroundColor Green
    Write-Host "     Login Server: $($acr.LoginServer)" -ForegroundColor Gray

    # Tikriname Repozitorijas (Images)
    # Bandome rasti bet kokį 'custom' vaizdą (ne tik hello-world)
    try {
        $repos = az acr repository list --name $acr.Name --output tsv 2>$null
        
        if ($repos) {
             if ($repos -match "hello-world") {
                 Write-Host "[OK] Bazinis vaizdas 'hello-world' rastas." -ForegroundColor Green
             }
             
             # Ieškome studento sukurto vaizdo (filtruojame hello-world)
             $customImages = $repos | Where-Object { $_ -notmatch "hello-world" }
             if ($customImages) {
                 Write-Host "[OK] Jūsų sukurtas vaizdas rastas: $customImages" -ForegroundColor Green
             } else {
                 Write-Host "[TRŪKSTA] Nerastas jūsų unikalus vaizdas (iš 2 dalies)." -ForegroundColor Yellow
                 Write-Host "           Ar atlikote 'docker push' komandą?"
             }
        } else {
             Write-Host "[KLAIDA] Registras tuščias (nėra vaizdų)." -ForegroundColor Red
        }
    } catch {
        Write-Host "[INFO] Nepavyko nuskaityti vaizdų sąrašo (gali reikėti 'az login')." -ForegroundColor Yellow
    }
} else {
    Write-Host "[KLAIDA] Nerastas Container Registry (ACR)" -ForegroundColor Red
}

# ---------------------------------------------------------
# 3. Virtuali Mašina (IaaS) ir Portai
# ---------------------------------------------------------
Write-Host "`n--- 2. Linux VM ir Portai ---" -ForegroundColor Cyan
$vm = Get-AzVM -ResourceGroupName $labRG.ResourceGroupName -Name "DockerVM" -ErrorAction SilentlyContinue

if ($vm) {
    Write-Host "[OK] Virtuali mašina 'DockerVM' rasta." -ForegroundColor Green
    
    # Tikriname Network Security Group (NSG) taisykles
    $nsg = Get-AzNetworkSecurityGroup -ResourceGroupName $labRG.ResourceGroupName | Select-Object -First 1
    if ($nsg) {
        $rules = $nsg.SecurityRules
        
        # Portas 80
        if ($rules | Where-Object { $_.DestinationPortRange -contains "80" -and $_.Access -eq "Allow" }) {
            Write-Host "[OK] Portas 80 (HTTP) atidarytas." -ForegroundColor Green
        } else {
            Write-Host "[TRŪKSTA] Portas 80 neatidarytas." -ForegroundColor Red
        }

        # Portas 9000 (Portainer)
        if ($rules | Where-Object { $_.DestinationPortRange -contains "9000" -and $_.Access -eq "Allow" }) {
            Write-Host "[OK] Portas 9000 (Portainer) atidarytas." -ForegroundColor Green
        } else {
            Write-Host "[TRŪKSTA] Portas 9000 neatidarytas (Portainer neveiks iš išorės)." -ForegroundColor Yellow
        }
    }
} else {
    Write-Host "[TRŪKSTA] Nerasta VM su pavadinimu 'DockerVM'." -ForegroundColor Red
}

# ---------------------------------------------------------
# 4. Azure Container Instance (Final Deploy)
# ---------------------------------------------------------
Write-Host "`n--- 3. Container Instance (Svetainė) ---" -ForegroundColor Cyan
$aci = Get-AzContainerGroup -ResourceGroupName $labRG.ResourceGroupName -ErrorAction SilentlyContinue | Select-Object -First 1

if ($aci) {
    if ($aci.State -eq "Succeeded" -or $aci.State -eq "Running") {
         Write-Host "[OK] Konteineris veikia: $($aci.Name)" -ForegroundColor Green
         if ($aci.IpAddress.Fqdn) {
             Write-Host "     Svetainės adresas: http://$($aci.IpAddress.Fqdn)" -ForegroundColor Cyan
         }
         
         # Tikriname ar naudojamas custom image (iš privataus registro)
         if ($aci.Containers[0].Image -match "azurecr.io") {
             Write-Host "[OK] Naudojamas privatus vaizdas iš ACR." -ForegroundColor Green
         } else {
             Write-Host "[PASTABA] Naudojamas viešas vaizdas (ne iš jūsų registro)." -ForegroundColor Yellow
         }

    } else {
         Write-Host "[KLAIDA] Konteineris yra būsenoje: $($aci.State)" -ForegroundColor Red
    }
} else {
    Write-Host "[KLAIDA] Nerastas veikiantis ACI konteineris." -ForegroundColor Red
}

Write-Host "`n--- TIKRINIMAS BAIGTAS ---" -ForegroundColor Cyan