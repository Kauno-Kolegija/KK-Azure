# configs/common.ps1

function Initialize-Lab {
    param (
        [string]$LocalConfigUrl
    )

    # 1. Konfigūracijų nuorodos
    $GlobalUrl = "https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/configs/global.json"
    
    # 2. Saugumo protokolas
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    # 3. Konfigūracijų atsisiuntimas
    try {
        $GlobalConfig = Invoke-RestMethod -Uri $GlobalUrl -ErrorAction Stop
        $LocalConfig  = Invoke-RestMethod -Uri $LocalConfigUrl -ErrorAction Stop
    } catch {
        Write-Error "KLAIDA: Nepavyko atsisiųsti konfigūracijos failų. Patikrinkite interneto ryšį."
        throw $_
    }

    # 4. Studento Identifikacija (Centralizuota logika!)
    $context = Get-AzContext
    if (-not $context) { Write-Error "Neprisijungta prie Azure! (Naudokite 'az login')"; exit }

    $StudentEmail = $null
    # Bandome Cloud Shell kintamąjį
    if ($env:ACC_USER_NAME -and $env:ACC_USER_NAME -match "@") {
        $StudentEmail = $env:ACC_USER_NAME
    } 
    # Jei ne, bandome CLI
    elseif (Get-Command az -ErrorAction SilentlyContinue) {
        try { $StudentEmail = az account show --query "user.name" -o tsv 2>$null } catch {}
    }
    
    # Jei vis tiek neradome, imame ID
    if (-not $StudentEmail -or $StudentEmail -match "MSI@") {
        $StudentEmail = "$($context.Account.Id) (System Identity)"
    }

    # 5. Antraštės išvedimas
    Clear-Host
    $Header = "$($GlobalConfig.KaunoKolegija) | $($GlobalConfig.ModuleName)"
    Write-Host "--- $Header ---" -ForegroundColor Cyan
    Write-Host "--- $($LocalConfig.LabName) ---" -ForegroundColor Yellow
    Write-Host "Studentas: $StudentEmail" -ForegroundColor DarkGray
    Write-Host "Vykdoma patikra..." -ForegroundColor Gray
    Write-Host ""

    # 6. Grąžiname objektą su visais duomenimis atgal į Lab skriptą
    return [PSCustomObject]@{
        GlobalConfig = $GlobalConfig
        LocalConfig  = $LocalConfig
        StudentEmail = $StudentEmail
        HeaderTitle  = $Header
    }
}