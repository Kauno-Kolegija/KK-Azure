function Initialize-Lab {
    param (
        [string]$LocalConfigUrl
    )

    # 1. Konfigūracijos ir protokolas
    $GlobalUrl = "https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/configs/global.json"
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    # 2. Siunčiame failus
    try {
        $GlobalConfig = Invoke-RestMethod -Uri $GlobalUrl -ErrorAction Stop
        $LocalConfig  = Invoke-RestMethod -Uri $LocalConfigUrl -ErrorAction Stop
    } catch {
        Write-Error "KLAIDA: Nepavyko atsisiųsti konfigūracijos (JSON)."
        throw $_
    }

    # 3. Identifikuojame studentą
    $context = Get-AzContext
    if (-not $context) { Write-Error "Neprisijungta prie Azure!"; exit }

    $StudentEmail = $null
    if ($env:ACC_USER_NAME -and $env:ACC_USER_NAME -match "@") {
        $StudentEmail = $env:ACC_USER_NAME
    } elseif (Get-Command az -ErrorAction SilentlyContinue) {
        try { $StudentEmail = az account show --query "user.name" -o tsv 2>$null } catch {}
    }
    
    if (-not $StudentEmail -or $StudentEmail -match "MSI@") {
        $StudentEmail = "$($context.Account.Id) (System Identity)"
    }

    # 4. VALOME EKRANĄ IR RODOME TIK GELTONĄ PRANEŠIMĄ
    Clear-Host
    Write-Host "Vykdoma patikra..." -ForegroundColor Yellow

    # 5. Grąžiname duomenis skriptui
    return [PSCustomObject]@{
        GlobalConfig = $GlobalConfig
        LocalConfig  = $LocalConfig
        StudentEmail = $StudentEmail
        HeaderTitle  = "$($GlobalConfig.KaunoKolegija) | $($GlobalConfig.ModuleName)"
    }
}