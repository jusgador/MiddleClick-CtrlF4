@echo off
rem ---------------------------------------------------------------------------
rem Parar-Remap.cmd
rem Encerra o remapeamento do botao do meio (util quando ele foi iniciado pelo
rem Iniciar-Remap.vbs, que roda sem janela e portanto sem Ctrl+C).
rem
rem ATENCAO: arquivo em ASCII puro (o cmd.exe le no codepage ANSI do sistema).
rem ---------------------------------------------------------------------------
setlocal

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$alvos = @(Get-CimInstance Win32_Process | Where-Object { ($_.Name -eq 'powershell.exe' -or $_.Name -eq 'pwsh.exe') -and $_.CommandLine -like '*Remap-MiddleClickToCtrlF4.ps1*' -and $_.ProcessId -ne $PID }); if ($alvos.Count -eq 0) { Write-Host 'O remapeamento nao esta em execucao.' -ForegroundColor Yellow } else { foreach ($p in $alvos) { Write-Host ('Parando o remapeamento (PID ' + $p.ProcessId + ')...') -ForegroundColor Green; Stop-Process -Id $p.ProcessId -Force } }"

echo.
pause
