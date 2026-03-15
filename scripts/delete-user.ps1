# 1. Pobierz profil użytkownika i usuń go (to usunie też pliki na dysku)
$user = Get-CimInstance -Class Win32_UserProfile | Where-Object { $_.LocalPath -like "*\NazwaUsera" }
if ($user) {
    Remove-CimInstance -CimInstance $user
    Write-Host "Profil i dane użytkownika zostały usunięte." -ForegroundColor Green
}

# 2. Usuń samo konto użytkownika (jeśli jeszcze istnieje)
if (Get-LocalUser -Name "NazwaUsera" -ErrorAction SilentlyContinue) {
    Remove-LocalUser -Name "NazwaUsera"
    Write-Host "Konto użytkownika zostało usunięte." -ForegroundColor Green
}