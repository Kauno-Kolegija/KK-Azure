# English launcher (same architecture as LAB07 and LAB08).
$Lang = 'EN'
try {
    Invoke-RestMethod `
        'https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/Lab11/Check-Lab11.ps1' `
        -ErrorAction Stop | Invoke-Expression
} catch {
    Write-Error 'Failed to load LAB 11 validation script.'
    throw
}
