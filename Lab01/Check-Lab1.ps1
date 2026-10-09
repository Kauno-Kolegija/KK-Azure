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
        Invoke-RestMethod `
            'https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/configs/common.ps1' `
            -ErrorAction Stop |
            Invoke-Expression
    }
}
catch {
    Write-Error "Failed to load common functions."
    throw
}

# --- 2. KALBA ---
if ($Lang -notin @("LT", "EN")) {
    $Lang = "LT"
}

# --- 3. INICIJUOJAME DARBA ---
$Setup = Initialize-Lab `
    -LocalConfigUrl "https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/Lab01/Check-Lab1-config.json" `
    -Lang $Lang

$GlobCfg = $Setup.GlobalConfig
$LocCfg  = $Setup.LocalConfig
$Msg     = $Setup.Messages
$LabMsg  = $LocCfg.Messages
$LabName = $LocCfg.LabName.$Lang

$TxtAccount          = $LocCfg.Checks.Account.$Lang
$TxtSubscriptionName = $LocCfg.Checks.SubscriptionName.$Lang
$TxtInstructorAccess = $LocCfg.Checks.InstructorAccess.$Lang
$TxtBudget           = $LocCfg.Checks.Budget.$Lang
$TxtAllowedLocations = $LocCfg.Checks.AllowedLocations.$Lang

$studentEmail = $Setup.StudentEmail
$context = Get-AzContext
$subscriptionId = $context.Subscription.Id
$subscriptionScope = "/subscriptions/$subscriptionId"

$results = @()

# ============================================================
# A. STUDENTO PASKYROS TIKRINIMAS
# ============================================================
try {
    if ($studentEmail -match '(?i)@itm\.kaunokolegija\.lt$') {
        Add-LabResult `
            -Results ([ref]$results) `
            -Name $TxtAccount `
            -Status "OK" `
            -Message $studentEmail `
            -Messages $Msg
    }
    else {
        Add-LabResult `
            -Results ([ref]$results) `
            -Name $TxtAccount `
            -Status "ERROR" `
            -Message "$($LabMsg.InvalidAccount.$Lang): $studentEmail" `
            -Messages $Msg
    }
}
catch {
    Add-LabResult `
        -Results ([ref]$results) `
        -Name $TxtAccount `
        -Status "WARNING" `
        -Message $LabMsg.AccountCheckFailed.$Lang `
        -Messages $Msg
}

# ============================================================
# B. PRENUMERATOS PAVADINIMO TIKRINIMAS
# ============================================================
try {
    $subName = $context.Subscription.Name

    # Priimami abu formatai nepriklausomai nuo pasirinktos kalbos.
    $isLtFormat = $subName -match $LocCfg.NamingPatterns.LT
    $isEnFormat = $subName -match $LocCfg.NamingPatterns.EN

    if ($isLtFormat -or $isEnFormat) {
        Add-LabResult `
            -Results ([ref]$results) `
            -Name $TxtSubscriptionName `
            -Status "OK" `
            -Message $subName `
            -Messages $Msg
    }
    else {
        Add-LabResult `
            -Results ([ref]$results) `
            -Name $TxtSubscriptionName `
            -Status "ERROR" `
            -Message "$subName ($($LabMsg.InvalidSubscriptionFormat.$Lang))" `
            -Messages $Msg
    }
}
catch {
    Add-LabResult `
        -Results ([ref]$results) `
        -Name $TxtSubscriptionName `
        -Status "WARNING" `
        -Message $LabMsg.SubscriptionCheckFailed.$Lang `
        -Messages $Msg
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
        $instructorAssignments |
        Where-Object { $_.Scope -eq $subscriptionScope }
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

        $otherCount = @(
            $allContributors | Where-Object {
                -not ($_.SignInName -and $_.SignInName -ieq $GlobCfg.InstructorEmail)
            }
        ).Count

        $suffix = if ($otherCount -gt 0) {
            " " + ($LabMsg.OtherContributors.$Lang -f $otherCount)
        }
        else {
            ""
        }

        Add-LabResult `
            -Results ([ref]$results) `
            -Name $TxtInstructorAccess `
            -Status "OK" `
            -Message "${displayName}${suffix}" `
            -Messages $Msg
    }
    elseif ($instructorAssignments.Count -gt 0) {
        $firstInstructor = $instructorAssignments | Select-Object -First 1

        $displayName = if ($firstInstructor.DisplayName) {
            $firstInstructor.DisplayName
        }
        elseif ($firstInstructor.SignInName) {
            $firstInstructor.SignInName
        }
        else {
            $LabMsg.InstructorFallbackName.$Lang
        }

        Add-LabResult `
            -Results ([ref]$results) `
            -Name $TxtInstructorAccess `
            -Status "WARNING" `
            -Message "$displayName ($($LabMsg.InstructorWrongScope.$Lang): $($firstInstructor.Scope))" `
            -Messages $Msg
    }
    elseif ($allContributors.Count -gt 0) {
        $firstOther = $allContributors | Select-Object -First 1

        $otherName = if ($firstOther.DisplayName) {
            $firstOther.DisplayName
        }
        elseif ($firstOther.SignInName) {
            $firstOther.SignInName
        }
        else {
            $LabMsg.OtherUserFallbackName.$Lang
        }

        Add-LabResult `
            -Results ([ref]$results) `
            -Name $TxtInstructorAccess `
            -Status "WARNING" `
            -Message "$otherName ($($LabMsg.InstructorNotFound.$Lang))" `
            -Messages $Msg
    }
    else {
        Add-LabResult `
            -Results ([ref]$results) `
            -Name $TxtInstructorAccess `
            -Status "ERROR" `
            -Message $LabMsg.NoContributorFound.$Lang `
            -Messages $Msg
    }
}
catch {
    Add-LabResult `
        -Results ([ref]$results) `
        -Name $TxtInstructorAccess `
        -Status "WARNING" `
        -Message "$($LabMsg.RoleCheckFailed.$Lang): $($_.Exception.Message)" `
        -Messages $Msg
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
            $budgetResponse = Invoke-AzRestMethod `
                -Method GET `
                -Uri $budgetUri `
                -ErrorAction Stop

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

        Add-LabResult `
            -Results ([ref]$results) `
            -Name $TxtBudget `
            -Status "OK" `
            -Message ($budgetNames -join ", ") `
            -Messages $Msg
    }
    else {
        Add-LabResult `
            -Results ([ref]$results) `
            -Name $TxtBudget `
            -Status "ERROR" `
            -Message $LabMsg.BudgetNotFound.$Lang `
            -Messages $Msg
    }
}
catch {
    Add-LabResult `
        -Results ([ref]$results) `
        -Name $TxtBudget `
        -Status "WARNING" `
        -Message "$($LabMsg.BudgetCheckFailed.$Lang): $($_.Exception.Message)" `
        -Messages $Msg
}

# ============================================================
# E. LEIDZIAMU AZURE REGIONU NUSTATYMAS
# ============================================================
try {
    $policyUri = "https://management.azure.com/subscriptions/$subscriptionId/providers/Microsoft.Authorization/policyAssignments?api-version=2026-06-01&`$filter=atScope()"

    $policyResponse = Invoke-AzRestMethod `
        -Method GET `
        -Uri $policyUri `
        -ErrorAction Stop

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
        Add-LabResult `
            -Results ([ref]$results) `
            -Name $TxtAllowedLocations `
            -Status "INFO" `
            -Message ($allowedLocations -join ", ") `
            -Messages $Msg
    }
    else {
        Add-LabResult `
            -Results ([ref]$results) `
            -Name $TxtAllowedLocations `
            -Status "INFO" `
            -Message $LabMsg.AllowedLocationsNotFound.$Lang `
            -Messages $Msg
    }
}
catch {
    Add-LabResult `
        -Results ([ref]$results) `
        -Name $TxtAllowedLocations `
        -Status "INFO" `
        -Message "$($LabMsg.AllowedLocationsCheckFailed.$Lang): $($_.Exception.Message)" `
        -Messages $Msg
}

# ============================================================
# GALUTINIS REZULTATAS
# ============================================================
Show-LabResults `
    -Setup $Setup `
    -LabName $LabName `
    -Results $results
