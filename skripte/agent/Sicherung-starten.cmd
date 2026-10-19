@echo off
title Hottgenroth-Projektdatenbank sichern
setlocal

echo.
echo   Hottgenroth-Projektdatenbank sichern
echo   ------------------------------------
echo   Nur lesend. Die Software darf offen bleiben - sie MUSS sogar offen
echo   bleiben, wenn gerade etwas versehentlich geloescht wurde.
echo.

rem Windows markiert alles, was aus einem ZIP oder Mailanhang kommt. Ohne das
rem Entfernen der Markierung bricht PowerShell mit einer Sicherheitsmeldung ab.
powershell -NoProfile -ExecutionPolicy Bypass -Command "Unblock-File -LiteralPath '%~dp0Sichere-Projektdatenbank.ps1'" >nul 2>&1

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Sichere-Projektdatenbank.ps1" %*

echo.
if errorlevel 1 (
  echo   Das hat nicht geklappt. Bitte den Text oben abfotografieren und an Dennis schicken.
) else (
  echo   Die Sicherung liegt im Ordner Hottgenroth-Rettung in deinem Benutzerordner.
)
echo.
pause
