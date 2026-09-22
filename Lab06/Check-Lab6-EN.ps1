# English launcher

$Lang = "EN"

try {
    Invoke-RestMethod `
        "https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/Lab06/Check-Lab6.ps1" `
        -ErrorAction Stop |
        Invoke-Expression
}
catch {
    Write-Error "Failed to load LAB 6 validation script."
    throw
}