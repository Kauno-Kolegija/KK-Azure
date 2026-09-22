# English launcher

$Lang = "EN"

try {
    Invoke-RestMethod `
        "https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/Lab05/Check-Lab5.ps1" `
        -ErrorAction Stop |
        Invoke-Expression
}
catch {
    Write-Error "Failed to load LAB 5 validation script."
    throw
}