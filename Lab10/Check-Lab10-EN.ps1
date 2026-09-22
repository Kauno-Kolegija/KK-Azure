# English launcher

$Lang = "EN"

try {
    Invoke-RestMethod `
        "https://raw.githubusercontent.com/Kauno-Kolegija/KK-Azure/main/Lab10/Check-Lab10.ps1" `
        -ErrorAction Stop |
        Invoke-Expression
}
catch {
    Write-Error "Failed to load LAB 10  validation script."
    throw
}