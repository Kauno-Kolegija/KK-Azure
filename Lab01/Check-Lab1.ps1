# ============================================================
# LAB 1 tikrinimo skriptas
# Kalba pagal nutylejima: LT
# EN kalba nustato Check-Lab1-EN.ps1 paleidiklis
# ============================================================

# --- 1. UZKRAUNAME BENDRAS FUNKCIJAS ---
try {
    if ($PSScriptRoot) {
        . (Join-Path $PSScriptRoot '../configs/common.ps1')
    }
    else {
        Invoke-RestMethod 'https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/configs/common.ps1' -ErrorAction Stop | Invoke-Expression
    }
}
catch {
    Write-Error "Failed to load common functions."
    throw
}

# --- 2. KALBA ---
if ($Lang -notin @("LT", "EN")) { $Lang = "LT" }

# --- 3. INICIJUOJAME DARBA ---
$Setup = Initialize-Lab `
    -LocalConfigUrl "https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/Lab01/Check-Lab1-config.json" `
    -Lang $Lang

$GlobCfg = $Setup.GlobalConfig
$LocCfg  = $Setup.LocalConfig

$Msg     = $GlobCfg.Messages.$Lang
$LabMsg  = $LocCfg.Messages
$LabName = $LocCfg.LabName.$Lang

$TxtAccount          = $LocCfg.Checks.Account.$Lang
$TxtSubscriptionName = $LocCfg.Checks.SubscriptionName.$Lang
$TxtInstructorAccess = $LocCfg.Checks.InstructorAccess.$Lang
$TxtBudget           = $LocCfg.Checks.Budget.$Lang
$TxtAllowedLocations = $LocCfg.Checks.AllowedLocations.$Lang

$studentEmail = $Setup.StudentEmail
$context      = Get-AzContext
$subscriptionId = $context.Subscription.Id
$subscriptionScope = "/subscriptions/$subscriptionId"


# ============================================================
# A. STUDENTO PASKYROS TIKRINIMAS
# ============================================================
try {
    if ($studentEmail -match '(?i)@itm\.kaunokolegija\.lt$') {
        $res0Text  = "[$($Msg.Ok)] - $studentEmail"
        $res0Color = "Green"
    }
    else {
        $res0Text  = "[$($Msg.Error)] - $($LabMsg.InvalidAccount.$Lang): $studentEmail"
        $res0Color = "Red"
    }
}
catch {
    $res0Text  = "[$($Msg.Warning)] - $($LabMsg.AccountCheckFailed.$Lang)"
    $res0Color = "Yellow"
}


# ============================================================
# B. PRENUMERATOS PAVADINIMO TIKRINIMAS
# ============================================================
try {
    $subName = $context.Subscription.Name

    # Priimami abu formatai nepriklausomai nuo pasirinktos kalbos:
    # LT: KT4-Mantas-Bartkevicius / KT-4-Mantas-Bartkevicius
    # EN: Erasmus-John-Smith
    $isLtFormat = $subName -match $LocCfg.NamingPatterns.LT
    $isEnFormat = $subName -match $LocCfg.NamingPatterns.EN

    if ($isLtFormat -or $isEnFormat) {
        $res1Text  = "[$($Msg.Ok)] - $subName"
        $res1Color = "Green"
    }
    else {
        $res1Text  = "[$($Msg.Error)] - $subName ($($LabMsg.InvalidSubscriptionFormat.$Lang))"
        $res1Color = "Red"
    }
}
catch {
    $res1Text  = "[$($Msg.Warning)] - $($LabMsg.SubscriptionCheckFailed.$Lang)"
    $res1Color = "Yellow"
}


# ============================================================
# C. DESTYTOJO TEISIU TIKRINIMAS
# ============================================================
try {
    $assignments = @(Get-AzRoleAssignment -ErrorAction Stop)

    # Visi Contributor priskyrimai, isskyrus paties studento paskyra.
    $allContributors = @(
        $assignments | Where-Object {
            $_.RoleDefinitionName -eq $LocCfg.RoleToCheck -and
            (-not $_.SignInName -or -not $studentEmail -or $_.SignInName -ine $studentEmail)
        }
    )

    # Konkretus destytojas pagal global.json InstructorEmail.
    $instructorAssignments = @(
        $allContributors | Where-Object {
            $_.SignInName -and $_.SignInName -ieq $GlobCfg.InstructorEmail
        }
    )

    $instructorAtSubscription = @(
        $instructorAssignments | Where-Object { $_.Scope -eq $subscriptionScope }
    ) | Select-Object -First 1

    if ($instructorAtSubscription) {
        if ($instructorAtSubscription.DisplayName) {
            $displayName = $instructorAtSubscription.DisplayName
        }
        elseif ($instructorAtSubscription.SignInName) {
            $displayName = $instructorAtSubscription.SignInName
        }
        else {
            $displayName = $LabMsg.InstructorFallbackName.$Lang
        }

        $otherCount = @($allContributors | Where-Object {
            -not ($_.SignInName -and $_.SignInName -ieq $GlobCfg.InstructorEmail)
        }).Count

        $suffix = if ($otherCount -gt 0) {
            " " + ($LabMsg.OtherContributors.$Lang -f $otherCount)
        } else { "" }

        $res2Text  = "[$($Msg.Ok)] - ${displayName}${suffix}"
        $res2Color = "Green"
    }
    elseif ($instructorAssignments.Count -gt 0) {
        # Dėstytojas rastas, bet Contributor suteiktas siauresneje apimtyje.
        $firstInstructor = $instructorAssignments | Select-Object -First 1
        $displayName = if ($firstInstructor.DisplayName) {
            $firstInstructor.DisplayName
        } elseif ($firstInstructor.SignInName) {
            $firstInstructor.SignInName
        } else {
            $LabMsg.InstructorFallbackName.$Lang
        }

        $res2Text  = "[$($Msg.Warning)] - $displayName ($($LabMsg.InstructorWrongScope.$Lang): $($firstInstructor.Scope))"
        $res2Color = "Yellow"
    }
    elseif ($allContributors.Count -gt 0) {
        # Contributor priskirtas, bet ne destytojui.
        $firstOther = $allContributors | Select-Object -First 1
        $otherName = if ($firstOther.DisplayName) {
            $firstOther.DisplayName
        } elseif ($firstOther.SignInName) {
            $firstOther.SignInName
        } else {
            $LabMsg.OtherUserFallbackName.$Lang
        }

        $res2Text  = "[$($Msg.Warning)] - $otherName ($($LabMsg.InstructorNotFound.$Lang))"
        $res2Color = "Yellow"
    }
    else {
        $res2Text  = "[$($Msg.Error)] - $($LabMsg.NoContributorFound.$Lang)"
        $res2Color = "Red"
    }
}
catch {
    # Technine patikros problema nera studento darbo klaida.
    $res2Text  = "[$($Msg.Warning)] - $($LabMsg.RoleCheckFailed.$Lang): $($_.Exception.Message)"
    $res2Color = "Yellow"
}


# ============================================================
# D. BUDGET TIKRINIMAS
# ============================================================
try {
    $accountsResponse = Invoke-AzRestMethod `
        -Method GET `
        -Uri "https://management.azure.com/providers/Microsoft.Billing/billingAccounts?api-version=2024-04-01" `
        -ErrorAction Stop

    $accounts = @((($accountsResponse.Content | ConvertFrom-Json).value))
    $foundBudgets = @()

    foreach ($account in $accounts) {
        $budgetUri = "https://management.azure.com/providers/Microsoft.Billing/billingAccounts/$($account.name)/providers/Microsoft.Consumption/budgets?api-version=2024-08-01"

        try {
            $budgetResponse = Invoke-AzRestMethod -Method GET -Uri $budgetUri -ErrorAction Stop
            $budgets = @((($budgetResponse.Content | ConvertFrom-Json).value))

            if ($budgets.Count -gt 0) {
                $foundBudgets += $budgets
            }
        }
        catch {
            # Jei vieno Billing Account nuskaityti nepavyksta, tikriname kitus.
        }
    }

    if ($foundBudgets.Count -gt 0) {
        $budgetNames = $foundBudgets | ForEach-Object { $_.name }
        $res3Text  = "[$($Msg.Ok)] - " + ($budgetNames -join ", ")
        $res3Color = "Green"
    }
    else {
        $res3Text  = "[$($Msg.Error)] - $($LabMsg.BudgetNotFound.$Lang)"
        $res3Color = "Red"
    }
}
catch {
    # Technine klaida -> Warning, nes nezinome, ar Budget tikrai neegzistuoja.
    $res3Text  = "[$($Msg.Warning)] - $($LabMsg.BudgetCheckFailed.$Lang): $($_.Exception.Message)"
    $res3Color = "Yellow"
}


# ============================================================
# E. LEIDZIAMU AZURE REGIONU NUSTATYMAS
# ============================================================
try {
    $policyUri = "https://management.azure.com/subscriptions/$subscriptionId/providers/Microsoft.Authorization/policyAssignments?api-version=2026-06-01&`$filter=atScope()"

    $policyResponse = Invoke-AzRestMethod -Method GET -Uri $policyUri -ErrorAction Stop
    $policyAssignments = @((($policyResponse.Content | ConvertFrom-Json).value))
    $allowedLocations = @()

    foreach ($assignment in $policyAssignments) {
        if ($assignment.properties.displayName -eq "Allowed resource deployment regions") {
            $parameters = $assignment.properties.parameters

            if ($parameters.allowedLocations.value) {
                $allowedLocations += @($parameters.allowedLocations.value)
            }

            if ($parameters.listOfAllowedLocations.value) {
                $allowedLocations += @($parameters.listOfAllowedLocations.value)
            }
        }
    }

    $allowedLocations = @($allowedLocations | Sort-Object -Unique)

    if ($allowedLocations.Count -gt 0) {
        $res4Text  = "[INFO] - " + ($allowedLocations -join ", ")
        $res4Color = "Cyan"
    }
    else {
        $res4Text  = "[INFO] - $($LabMsg.AllowedLocationsNotFound.$Lang)"
        $res4Color = "Yellow"
    }
}
catch {
    $res4Text  = "[INFO] - $($LabMsg.AllowedLocationsCheckFailed.$Lang): $($_.Exception.Message)"
    $res4Color = "Yellow"
}


# ============================================================
# GALUTINIS REZULTATAS
# ============================================================

Show-LabResults `
    -Setup $Setup `
    -LabName $LabName `
    -Results $results