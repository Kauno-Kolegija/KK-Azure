# --- VERSIJOS KONTROLĖ ---
$ScriptVersion = "LAB 8 TIKRINIMAS: Web Apps & Monitoring (Final)"
Clear-Host
Write-Host "--------------------------------------------------"
Write-Host $ScriptVersion -ForegroundColor Magenta
Write-Host "Vykdoma konfigūracijos patikra..."
Write-Host "--------------------------------------------------"

# --- 1. PASIRUOŠIMAS ---
$resourceResults = @()

# Bandome gauti resursų grupę
$labRG = Get-AzResourceGroup | Where-Object { $_.ResourceGroupName -match "RG-LAB08" } | Select-Object -First 1

# A. Resursų Grupė
if ($labRG) {
    $rgText = "[OK] - Rasta grupė ($($labRG.ResourceGroupName))"
    $rgColor = "Green"
} else {
    $rgText = "[KLAIDA] - Nerasta grupė, prasidedanti 'RG-LAB08...'"
    $rgColor = "Red"
}
$resourceResults += [PSCustomObject]@{ Name = "Resursų grupė"; Text = $rgText; Color = $rgColor }

if ($labRG) {
    # B. App Service Plan (Planas ir Scale Out)
    # Priverstinai atnaujiname plano informaciją, kad matytume naujausią serverių skaičių
    $appPlan = Get-AzAppServicePlan | Where-Object { $_.ResourceGroup -eq $labRG.ResourceGroupName } | Select-Object -First 1
    
    if ($appPlan) {
        # Tikriname ar planas yra mokamas
        $tier = $appPlan.Sku.Tier
        if ($tier -ne "Free" -and $tier -ne "Shared") {
            $planStatus = "[OK] - Planas tinkamas ($tier - $($appPlan.Sku.Name))"
            $planColor = "Green"
        } else {
            $planStatus = "[KLAIDA] - Pasirinktas nemokamas planas ($tier). Reikia S1 arba P0v3"
            $planColor = "Red"
        }

        # Tikriname Scale Out (Serverių skaičių)
        # Naudojame Sku.Capacity, nes tai tiksliausias rodiklis
        $serverCount = $appPlan.Sku.Capacity
        if ($serverCount -ge 2) {
            $scaleStatus = "[OK] - Scale Out aktyvus (Serverių: $serverCount)"
            $scaleColor = "Green"
        } else {
            $scaleStatus = "[TRŪKSTA] - Naudojamas tik $serverCount serveris. Padidinkite iki 2."
            $scaleColor = "Red"
        }

    } else {
        $planStatus = "[KLAIDA] - Nerastas App Service planas"
        $planColor = "Red"
        $scaleStatus = "-"
        $scaleColor = "Gray"
    }
    
    $resourceResults += [PSCustomObject]@{ Name = "Planas (Pricing)"; Text = $planStatus; Color = $planColor }
    $resourceResults += [PSCustomObject]@{ Name = "Skalieravimas"; Text = $scaleStatus; Color = $scaleColor }

    # C. Web App ir Slots
    $webApp = Get-AzWebApp -ResourceGroupName $labRG.ResourceGroupName | Select-Object -First 1
    
    if ($webApp) {
        $webText = "[OK] - Web App rasta ($($webApp.Name))"
        $webColor = "Green"
        
        # Tikriname 'testavimo-aplinka' lizdą
        $slots = Get-AzWebAppSlot -ResourceGroupName $labRG.ResourceGroupName -Name $webApp.Name
        $targetSlot = $slots | Where-Object { $_.Name -match "testavimo-aplinka" }

        if ($targetSlot) {
            $slotText = "[OK] - Rastas lizdas 'testavimo-aplinka'"
            $slotColor = "Green"
        } else {
            $slotText = "[TRŪKSTA] - Nerastas Deployment Slot 'testavimo-aplinka'"
            $slotColor = "Red"
        }
    } else {
        $webText = "[KLAIDA] - Nerasta Web App"
        $webColor = "Red"
        $slotText = "-"
        $slotColor = "Gray"
    }
    
    $resourceResults += [PSCustomObject]@{ Name = "Web Aplikacija"; Text = $webText; Color = $webColor }
    $resourceResults += [PSCustomObject]@{ Name = "Deployment Slots"; Text = $slotText; Color = $slotColor }

    # D. Monitoringas ir Alerts
    $alerts = Get-AzMetricAlertRuleV2 -ResourceGroupName $labRG.ResourceGroupName -ErrorAction SilentlyContinue
    
    if ($alerts -and $alerts.Count -ge 1) {
        $alertText = "[OK] - Rasta Alert taisyklė ($($alerts[0].Name))"
        $alertColor = "Green"
    } else {
        $alertText = "[TRŪKSTA] - Nesukurtas 'Alert Rule' (Monitoringas)"
        $alertColor = "Red"
    }
    $resourceResults += [PSCustomObject]@{ Name = "Alerts (Įspėjimai)"; Text = $alertText; Color = $alertColor }
}

# --- 3. REZULTATŲ IŠVEDIMAS ---
$date = Get-Date -Format "yyyy-MM-dd HH:mm"
$user = az ad signed-in-user show --query userPrincipalName -o tsv

Write-Host "`n--- GALUTINIS REZULTATAS ---" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Gray
Write-Host "LAB 08: Azure Web Apps & Monitoring" -ForegroundColor Yellow
Write-Host "Data: $date"
Write-Host "Studentas: $user"
Write-Host "==================================================" -ForegroundColor Gray

foreach ($res in $resourceResults) {
    $label = "$($res.Name):"
    # Lygiavimas
    $targetWidth = 25
    $neededSpaces = $targetWidth - $label.Length
    if ($neededSpaces -lt 1) { $neededSpaces = 1 }
    $padding = " " * $neededSpaces
    
    Write-Host "$label$padding" -NoNewline
    Write-Host $res.Text -ForegroundColor $res.Color
}
Write-Host "==================================================" -ForegroundColor Gray
Write-Host ""