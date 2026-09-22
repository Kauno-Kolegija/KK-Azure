# ============================================================
# LAB 1 tikrinimo skriptas
# Kalba pagal nutylėjimą: LT
# EN kalbą nustato Check-Lab1-EN.ps1 paleidiklis
# ============================================================

# --- 1. UŽKRAUNAME BENDRAS FUNKCIJAS ---
try {
    if ($PSScriptRoot) {
        . (Join-Path $PSScriptRoot '../configs/common.ps1')
    }
    else {
        Invoke-RestMethod `
            'https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/configs/common.ps1' `
            -ErrorAction Stop |
            Invoke-Expression
    }
}
catch {
    # Ši klaida rodoma dar prieš užkraunant kalbų konfigūraciją
    Write-Error "Failed to load common functions."
    throw
}


# --- 2. KALBA ---
if ($Lang -notin @("LT", "EN")) {
    $Lang = "LT"
}


# --- 3. INICIJUOJAME DARBĄ ---
$Setup = Initialize-Lab `
    -LocalConfigUrl "https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/Lab01/Check-Lab1-config.json" `
    -Lang $Lang

$GlobCfg = $Setup.GlobalConfig
$LocCfg  = $Setup.LocalConfig

# Bendri tekstai
$Msg = $GlobCfg.Messages.$Lang

# LAB1 tekstai
$LabMsg = $LocCfg.Messages
$LabName = $LocCfg.LabName.$Lang

$TxtAccount          = $LocCfg.Checks.Account.$Lang
$TxtSubscriptionName = $LocCfg.Checks.SubscriptionName.$Lang
$TxtInstructorAccess = $LocCfg.Checks.InstructorAccess.$Lang
$TxtBudget           = $LocCfg.Checks.Budget.$Lang

$studentEmail = $Setup.StudentEmail


# ============================================================
# A. STUDENTO PASKYROS TIKRINIMAS
# ============================================================

try {
    if ($studentEmail -match '(?i)@itm\.kaunokolegija\.lt$') {
        $res0Text  = "[$($Msg.Ok)] - $studentEmail"
        $res0Color = "Green"
    }
    else {
        $res0Text = "[$($Msg.Error)] - $($LabMsg.InvalidAccount.$Lang): $studentEmail"
        $res0Color = "Red"
    }
}
catch {
    $res0Text  = "[$($Msg.Error)] - $($LabMsg.AccountCheckFailed.$Lang)"
    $res0Color = "Red"
}


# ============================================================
# B. PRENUMERATOS PAVADINIMO TIKRINIMAS
# ============================================================

$context = Get-AzContext
$subName = $context.Subscription.Name

$isNameCorrect = $subName -match $LocCfg.NamingPattern

if ($isNameCorrect) {
    $res1Text  = "[$($Msg.Ok)] - $subName"
    $res1Color = "Green"
}
else {
    $res1Text = "[$($Msg.Error)] - $subName ($($LabMsg.InvalidSubscriptionFormat.$Lang))"
    $res1Color = "Red"
}


# ============================================================
# C. DĖSTYTOJO TEISIŲ TIKRINIMAS
# ============================================================

try {
    $assignments = Get-AzRoleAssignment -ErrorAction SilentlyContinue

    $allContributors = @()

    if ($assignments) {
        foreach ($a in $assignments) {

            $isContributor =
                $a.RoleDefinitionName -eq $LocCfg.RoleToCheck

            $isStudent =
                $a.SignInName -and
                $studentEmail -and
                ($a.SignInName -ieq $studentEmail)

            if ($isContributor -and -not $isStudent) {
                $allContributors += $a
            }
        }
    }


    # Ieškome konkrečiai dėstytojo pagal global.json el. paštą
    $instructor = $null

    foreach ($c in $allContributors) {
        if (
            $c.SignInName -and
            ($c.SignInName -ieq $GlobCfg.InstructorEmail)
        ) {
            $instructor = $c
            break
        }
    }


    if ($instructor) {

        $displayName = if ($instructor.DisplayName) {
            $instructor.DisplayName
        }
        elseif ($instructor.SignInName) {
            $instructor.SignInName
        }
        else {
            $LabMsg.InstructorFallbackName.$Lang
        }


        $otherCount = $allContributors.Count - 1

        if ($otherCount -gt 0) {
            $suffix = " " + (
                $LabMsg.OtherContributors.$Lang -f $otherCount
            )
        }
        else {
            $suffix = ""
        }


        $res2Text  = "[$($Msg.Ok)] - ${displayName}${suffix}"
        $res2Color = "Green"
    }
    elseif ($allContributors.Count -gt 0) {

        $firstOther = $allContributors[0]

        $otherName = if ($firstOther.DisplayName) {
            $firstOther.DisplayName
        }
        elseif ($firstOther.SignInName) {
            $firstOther.SignInName
        }
        else {
            $LabMsg.OtherUserFallbackName.$Lang
        }

        $res2Text = "[$($Msg.Error)] - $otherName ($($LabMsg.InstructorNotFound.$Lang))"
        $res2Color = "Yellow"
    }
    else {
        $res2Text = "[$($Msg.Error)] - $($LabMsg.NoContributorFound.$Lang)"
        $res2Color = "Red"
    }
}
catch {
    $res2Text = "[$($Msg.Error)] - $($LabMsg.RoleCheckFailed.$Lang): $($_.Exception.Message)"
    $res2Color = "Red"
}


# ============================================================
# D. BUDGET TIKRINIMAS
# ============================================================

try {
    # Gauname vartotojui prieinamus Billing Accounts
    $accountsResponse = Invoke-AzRestMethod `
        -Method GET `
        -Uri "https://management.azure.com/providers/Microsoft.Billing/billingAccounts?api-version=2024-04-01" `
        -ErrorAction Stop

    $accounts = (
        $accountsResponse.Content |
        ConvertFrom-Json
    ).value


    $foundBudgets = @()


    foreach ($account in $accounts) {

        $budgetUri = `
            "https://management.azure.com/providers/Microsoft.Billing/billingAccounts/$($account.name)/providers/Microsoft.Consumption/budgets?api-version=2024-08-01"

        try {
            $budgetResponse = Invoke-AzRestMethod `
                -Method GET `
                -Uri $budgetUri `
                -ErrorAction Stop

            $budgets = (
                $budgetResponse.Content |
                ConvertFrom-Json
            ).value


            if ($budgets) {
                $foundBudgets += $budgets
            }
        }
        catch {
            # Jei vieno Billing Account nepavyksta nuskaityti,
            # tikriname kitus.
        }
    }


    if ($foundBudgets.Count -gt 0) {

        $budgetNames = $foundBudgets |
            ForEach-Object {
                $_.name
            }

        $res3Text = "[$($Msg.Ok)] - " + ($budgetNames -join ", ")
        $res3Color = "Green"
    }
    else {
        $res3Text = "[$($Msg.Error)] - $($LabMsg.BudgetNotFound.$Lang)"
        $res3Color = "Red"
    }
}
catch {
    $res3Text = "[$($Msg.Error)] - $($LabMsg.BudgetCheckFailed.$Lang): $($_.Exception.Message)"
    $res3Color = "Red"
}


# ============================================================
# GALUTINIS REZULTATAS
# ============================================================

$date = Get-Date -Format "yyyy-MM-dd HH:mm"

Write-Host ""
Write-Host "--- $($Msg.FinalResult) ---" -ForegroundColor Cyan

Write-Host "==================================================" -ForegroundColor Gray

Write-Host $Setup.HeaderTitle
Write-Host $LabName -ForegroundColor Yellow

Write-Host "$($Msg.Date): $date"
Write-Host "$($Msg.Student): $studentEmail"

Write-Host "==================================================" -ForegroundColor Gray


Write-Host ("1. {0,-27}" -f ($TxtAccount + ":")) -NoNewline
Write-Host $res0Text -ForegroundColor $res0Color


Write-Host ("2. {0,-27}" -f ($TxtSubscriptionName + ":")) -NoNewline
Write-Host $res1Text -ForegroundColor $res1Color


Write-Host ("3. {0,-27}" -f ($TxtInstructorAccess + ":")) -NoNewline
Write-Host $res2Text -ForegroundColor $res2Color


Write-Host ("4. {0,-27}" -f ($TxtBudget + ":")) -NoNewline
Write-Host $res3Text -ForegroundColor $res3Color


Write-Host "==================================================" -ForegroundColor Gray
Write-Host ""