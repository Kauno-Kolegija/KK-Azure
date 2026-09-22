# English launcher

$Lang = "EN"

try {
    Invoke-RestMethod `
        "https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/Lab02/Check-Lab2.ps1" `
        -ErrorAction Stop |
        Invoke-Expression
}
catch {
    Write-Error "Failed to load LAB 2 validation script."
    throw
}