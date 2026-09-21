function Initialize-Lab {
    param (
        [string]$LocalConfigUrl,
        [string]$ConfigDirectory
    )

    # 1. Konfigūracijos ir protokolas
    $GlobalUrl = "https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/configs/global.json"
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    # 2. Siunčiame failus
    try {
        if ($ConfigDirectory) {
            $globalPath = Join-Path $ConfigDirectory '../configs/global.json'
            $localPath = Join-Path $ConfigDirectory ([IO.Path]::GetFileName(([uri]$LocalConfigUrl).AbsolutePath))
            $GlobalConfig = Get-Content -LiteralPath $globalPath -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            $LocalConfig = Get-Content -LiteralPath $localPath -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        } else {
            $GlobalConfig = Invoke-RestMethod -Uri $GlobalUrl -ErrorAction Stop
            $LocalConfig = Invoke-RestMethod -Uri $LocalConfigUrl -ErrorAction Stop
        }
        if (-not $LocalConfig.LabName) { throw 'Konfigūracijoje trūksta LabName.' }
    } catch {
        Write-Error "KLAIDA: Nepavyko atsisiųsti konfigūracijos (JSON)."
        throw $_
    }

    # 3. Identifikuojame studentą
    $context = Get-AzContext
    if (-not $context) { throw 'Neprisijungta prie Azure!' }

    $StudentEmail = $context.Account.Id
    if ($env:ACC_USER_NAME -and $env:ACC_USER_NAME -match "@") {
        $StudentEmail = $env:ACC_USER_NAME
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

# Patvirtiname tik konkrečiam vartotojui tiesiogiai suteiktą rolę prenumeratoje.
# Jei Graph neleidžia nustatyti vartotojo, kvietėjas turi rodyti patikros klaidą.
function Test-LabInstructorRole {
    param([string]$Email, [string]$RoleName, [string]$SubscriptionId)
    if (-not $Email -or -not $RoleName -or -not $SubscriptionId) {
        throw 'Trūksta dėstytojo, rolės arba prenumeratos konfigūracijos.'
    }
    $scope = "/subscriptions/$SubscriptionId"
    $assignments = @(Get-AzRoleAssignment -SignInName $Email -Scope $scope -ErrorAction Stop)
    return @($assignments | Where-Object {
        $_.RoleDefinitionName -eq $RoleName -and $_.Scope.TrimEnd('/') -eq $scope
    }).Count -gt 0
}

function Test-LabPortRange {
    param($Ranges, [int]$Port)
    foreach ($range in @($Ranges)) {
        if ($range -eq '*' -or $range -eq "$Port") { return $true }
        if ($range -match '^(\d+)-(\d+)$' -and $Port -ge [int]$Matches[1] -and $Port -le [int]$Matches[2]) { return $true }
    }
    return $false
}

# Tai taisyklių konfigūracijos patikra, ne pasiekiamumo testas.
# Ankstesnė priešingo veiksmo taisyklė gali pakeisti rezultatą: tokiu atveju OK neteikiame.
function Get-LabNsgPortRule {
    param($Nsg, [int]$Port, [ValidateSet('Allow', 'Deny')][string]$Access)
    $rules = @($Nsg.SecurityRules | Where-Object {
        $_.Direction -eq 'Inbound' -and $_.Protocol -in @('Tcp', '*') -and
        (Test-LabPortRange -Ranges (@($_.DestinationPortRange) + @($_.DestinationPortRanges)) -Port $Port)
    } | Sort-Object Priority)
    if ($rules.Count -gt 0 -and $rules[0].Access -eq $Access) { return $rules[0] }
}
