@echo off
rem ---------------------------------------------------------------------------
rem Instalar.cmd
rem Instala o remapeamento (botao do meio -> CTRL+F4 + aceleracao da rolagem)
rem a partir DESTA pasta. Duplo clique e responda a pergunta.
rem
rem   - desbloqueia os arquivos (marca de "baixado da internet");
rem   - para uma instancia antiga, se houver (para carregar a versao nova);
rem   - pergunta se deve iniciar com o Windows (cria ou remove o atalho na
rem     pasta Inicializar);
rem   - liga o remapeamento agora.
rem
rem Pode rodar de novo a qualquer momento (para atualizar ou mudar a resposta).
rem Depois de instalar, NAO mova nem apague esta pasta: o atalho aponta para ela.
rem
rem ATENCAO: arquivo em ASCII puro (o cmd.exe le no codepage ANSI do sistema).
rem ---------------------------------------------------------------------------
setlocal

set "PASTA=%~dp0"
if "%PASTA:~-1%"=="\" set "PASTA=%PASTA:~0,-1%"
set "ATALHO_NOME=Remap botao do meio.lnk"

echo.
echo   Instalacao do remapeamento do mouse
echo   - botao do meio  -^> CTRL+F4
echo   - roda girando continuamente -^> rolagem acelerada
echo.
echo   Pasta: %PASTA%
echo.

if not exist "%PASTA%\Iniciar-Remap.vbs" goto faltaArquivo
if not exist "%PASTA%\Remap-MiddleClickToCtrlF4.ps1" goto faltaArquivo

rem 1) Pergunta sobre a inicializacao automatica (antes de mexer em qualquer coisa).
set /a TENTATIVAS=0
:pergunta
set /a TENTATIVAS+=1
if %TENTATIVAS% gtr 5 goto cancelado
set "RESP="
set /p "RESP=Iniciar automaticamente com o Windows? (S/N): "
if /i "%RESP%"=="S" set "AUTO=S" & goto preparar
if /i "%RESP%"=="N" set "AUTO=N" & goto preparar
echo   Responda S ou N.
goto pergunta

:preparar
rem 2) Desbloqueia os arquivos baixados (evita aviso de seguranca do Windows).
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Get-ChildItem -LiteralPath $env:PASTA -Recurse -File | Unblock-File"

rem 3) Para uma instancia antiga, se houver (para carregar a versao nova).
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Get-CimInstance Win32_Process | Where-Object { ($_.Name -eq 'powershell.exe' -or $_.Name -eq 'pwsh.exe') -and $_.CommandLine -like '*Remap-MiddleClickToCtrlF4.ps1*' -and $_.ProcessId -ne $PID } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }"

if "%AUTO%"=="N" goto semAuto

:comAuto
rem 4) Cria ou remove o atalho na pasta Inicializar.
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$q = [char]34; $l = (New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path ([Environment]::GetFolderPath('Startup')) $env:ATALHO_NOME)); $l.TargetPath = Join-Path $env:SystemRoot 'System32\wscript.exe'; $l.Arguments = $q + (Join-Path $env:PASTA 'Iniciar-Remap.vbs') + $q; $l.WorkingDirectory = $env:PASTA; $l.Description = 'Botao do meio do mouse -> CTRL+F4 + aceleracao da rolagem'; $l.Save()"
echo   OK: vai iniciar junto com o Windows.
goto iniciar

:semAuto
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$a = Join-Path ([Environment]::GetFolderPath('Startup')) $env:ATALHO_NOME; if (Test-Path -LiteralPath $a) { Remove-Item -LiteralPath $a -Force }"
echo   OK: NAO vai iniciar com o Windows (para ligar, rode Iniciar-Remap.vbs).
goto iniciar

:iniciar
rem 5) Liga agora.
start "" wscript.exe "%PASTA%\Iniciar-Remap.vbs"

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$fim = (Get-Date).AddSeconds(20); do { Start-Sleep -Milliseconds 500; $p = @(Get-CimInstance Win32_Process | Where-Object { $_.Name -eq 'powershell.exe' -and $_.CommandLine -like '*-File*Remap-MiddleClickToCtrlF4.ps1*' -and $_.ProcessId -ne $PID }) } until ($p.Count -gt 0 -or (Get-Date) -gt $fim); if ($p.Count -gt 0) { Write-Host '  OK: remapeamento ligado.' -ForegroundColor Green } else { Write-Host '  ATENCAO: o remapeamento nao subiu. Tente dar duplo clique em Iniciar-Remap.vbs.' -ForegroundColor Yellow }"

echo.
echo   Para parar: Parar-Remap.cmd    Para mudar a resposta: rode este arquivo de novo.
echo.
pause
exit /b 0

:cancelado
echo.
echo   Instalacao cancelada: nenhuma resposta valida. Nada foi alterado.
echo.
pause
exit /b 1

:faltaArquivo
echo   ERRO: nao encontrei Iniciar-Remap.vbs e Remap-MiddleClickToCtrlF4.ps1 nesta pasta.
echo   Extraia o ZIP inteiro antes de rodar o Instalar.cmd.
echo.
pause
exit /b 1
