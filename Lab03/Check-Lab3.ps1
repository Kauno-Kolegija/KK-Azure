# --- 1. UŽKRAUNAME BENDRAS FUNKCIJAS ---
try {
    irm "https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/configs/common.ps1" | iex
} catch {
    Write-Error "Nepavyko užkrauti bazinių funkcijų (common.ps1)."
    exit
}

# --- 2. INICIJUOJAME DARBĄ ---
$Setup = Initialize-Lab -LocalConfigUrl "https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/Lab03/Check-Lab3-config.json"
$LocCfg = $Setup.LocalConfig

# --- 3. DUOMENŲ RINKIMAS ---

# A. Randame Resursų grupę
$targetRG = Get-AzResourceGroup | Where-Object { $_.ResourceGroupName -match "RG-LAB03" } | Select-Object -First 1

if ($targetRG) {
    # Tikriname regioną (Turi būti Norway East pagal 30 punktą)
    if ($targetRG.Location -eq "norwayeast") {
        $rgText  = "[OK] - $($targetRG.ResourceGroupName) (Norway East)"
        $rgColor = "Green"
    } else {
        $rgText  = "[DĖMESIO] - $($targetRG.ResourceGroupName) (Yra: $($targetRG.Location), Reikėjo: norwayeast)"
        $rgColor = "Yellow"
    }
} else {
    $rgText  = "[KLAIDA] - Nerasta grupė RG-LAB03..."
    $rgColor = "Red"
}

# B. Resursų tikrinimas
$resourceResults = @()

# 1. Resursų Grupė
$resourceResults += [PSCustomObject]@{
    Name  = "Resursų grupė"
    Text  = $rgText
    Color = $rgColor
}

if ($targetRG) {
    # --- 1. VIRTUALUS SERVERIS (VM) ---
    $vm = Get-AzVM -ResourceGroupName $targetRG.ResourceGroupName | Select-Object -First 1
    
    if ($vm) {
        $actualSize = $vm.HardwareProfile.VmSize
        $expectedSize = "Standard_B1ms"
        
        # Būsena
        $statusObj = Get-AzVM -ResourceGroupName $targetRG.ResourceGroupName -Name $vm.Name -Status
        $displayStatus = ($statusObj.Statuses | Where-Object Code -like "PowerState/*" | Select-Object -First 1).DisplayStatus
        
        # Diskas (46-49 punktai reikalauja papildomo disko)
        $dataDisks = $vm.StorageProfile.DataDisks
        $diskCount = $dataDisks.Count
        
        if ($actualSize -eq $expectedSize) {
            $vmText = "[OK] - $($vm.Name) ($actualSize) [$displayStatus]"
            $vmColor = "Green"
        } else {
            $vmText = "[DĖMESIO] - $($vm.Name). Dydis: $actualSize (Reikėjo: $expectedSize)"
            $vmColor = "Yellow"
        }

        # Atskiras įrašas diskui
        if ($diskCount -ge 1) {
            $diskText = "[OK] - Rasta papildomų diskų: $diskCount (128 GiB)"
            $diskColor = "Green"
        } else {
            $diskText = "[TRŪKSTA] - Nėra papildomo duomenų disko (Data Disk)"
            $diskColor = "Red"
        }

    } else {
        $vmText = "[TRŪKSTA] - Nerastas Virtualus Serveris"
        $vmColor = "Red"
        $diskText = "---"
        $diskColor = "Gray"
    }

    $resourceResults += [PSCustomObject]@{ Name = "Virtualus Serveris"; Text = $vmText; Color = $vmColor }
    if ($vm) {
        $resourceResults += [PSCustomObject]@{ Name = " - Duomenų diskas"; Text = $diskText; Color = $diskColor }
    }

    # --- 2. FUNCTION APP ---
    $funcApp = Get-AzResource -ResourceGroupName $targetRG.ResourceGroupName -ResourceType "Microsoft.Web/sites" | Where-Object { $_.Kind -like "*functionapp*" } | Select-Object -First 1
    
    if ($funcApp) {
        $resourceResults += [PSCustomObject]@{
            Name  = "Function App"
            Text  = "[OK] - $($funcApp.Name)"
            Color = "Green"
        }

        # --- 3. FUNKCIJOS (AZURE CLI METODAS) ---
        Write-Host "   (Tikrinama funkcijų būsena...)" -ForegroundColor DarkGray
        
        try {
            $cliOutput = az functionapp function list --resource-group $targetRG.ResourceGroupName --name $funcApp.Name --output json 2>$null | ConvertFrom-Json
        } catch {
            $cliOutput = @()
        }

        # HTTP (-fun1)
        $fun1 = $cliOutput | Where-Object { $_.name -like "*/$($Setup.LastName)-fun1" -or $_.name -like "*/*-fun1" } | Select-Object -First 1
        
        if ($fun1) {
            $cleanName = $fun1.name.Split('/')[-1]
            $resourceResults += [PSCustomObject]@{ Name = "Funkcija (HTTP)"; Text = "[OK] - $cleanName"; Color = "Green" }
        } else {
            $resourceResults += [PSCustomObject]@{ Name = "Funkcija (HTTP)"; Text = "[TRŪKSTA] - Nerasta funkcija *-fun1"; Color = "Red" }
        }

        # Timer (-fun2)
        $fun2 = $cliOutput | Where-Object { $_.name -like "*/$($Setup.LastName)-fun2" -or $_.name -like "*/*-fun2" } | Select-Object -First 1
        
        if ($fun2) {
            $cleanName = $fun2.name.Split('/')[-1]
            $resourceResults += [PSCustomObject]@{ Name = "Funkcija (Timer)"; Text = "[OK] - $cleanName"; Color = "Green" }
        } else {
            $resourceResults += [PSCustomObject]@{ Name = "Funkcija (Timer)"; Text = "[TRŪKSTA] - Nerasta funkcija *-fun2"; Color = "Red" }
        }

    } else {
        $resourceResults += [PSCustomObject]@{ Name = "Function App"; Text = "[TRŪKSTA] - Nerasta Function App"; Color = "Red" }
    }

} else {
    $resourceResults += [PSCustomObject]@{ Name = "Virtualus Serveris"; Text = "[KLAIDA] - Nėra grupės"; Color = "Gray" }
    $resourceResults += [PSCustomObject]@{ Name = "Function App"; Text = "[KLAIDA] - Nėra grupės"; Color = "Gray" }
}

# --- 4. IŠVEDIMAS ---
$date = Get-Date -Format "yyyy-MM-dd HH:mm"

Write-Host "`n--- GALUTINIS REZULTATAS (Padarykite nuotrauką) ---" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Gray
Write-Host "$($Setup.HeaderTitle)"
if ($LocCfg.LabName) { Write-Host "$($LocCfg.LabName)" -ForegroundColor Yellow } else { Write-Host "LAB 3: Compute" -ForegroundColor Yellow }
Write-Host "Data: $date"
Write-Host "Studentas: $($Setup.StudentEmail)"
Write-Host "==================================================" -ForegroundColor Gray

$i = 1
foreach ($res in $resourceResults) {
    if ($res.Name -match "^ -") {
        # Papildomas diskas (įtrauka)
        $label = "   $($res.Name):"
    } else {
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