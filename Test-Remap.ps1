#Requires -Version 5.1
<#
.SYNOPSIS
    Teste automatizado do remapeamento: prova a cadeia inteira sem clique humano.

.DESCRIPTION
    Sobe o Remap-MiddleClickToCtrlF4.ps1 num processo separado, injeta input
    sintetico (mouse_event) e confere cinco coisas:

      1. O clique do meio NAO chega na janela de teste  -> foi suprimido.
      2. O CTRL+F4 CHEGA na janela de teste              -> o atalho foi enviado.
      3. A rolagem CHEGA na janela de teste              -> o hook nao toca WM_MOUSEWHEEL.
      4. O botao esquerdo CHEGA na janela de teste       -> outros botoes intactos.
      5. O encerramento por -MaxSeconds desinstala o hook e o processo sai sozinho.

    A janela de teste e' um form vazio: nada nela pode ser fechado ou alterado sem
    querer. O cursor do mouse e' movido durante o teste e restaurado no final.

    Encerramento: exit code 0 = passou, 1 = falhou.

.PARAMETER KeepLog
    Nao apaga os arquivos de log em %TEMP% no final (para investigar uma falha).

.EXAMPLE
    .\Test-Remap.ps1
#>
[CmdletBinding()]
param(
    [switch]$KeepLog
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# WinForms + Application.Run exigem apartamento STA. O Windows PowerShell 5.1 ja
# e' STA; se alguem rodar num host MTA, melhor falhar claro do que dar erro
# esquisito no meio do teste.
$apartamento = [System.Threading.Thread]::CurrentThread.GetApartmentState()
if ($apartamento -ne [System.Threading.ApartmentState]::STA) {
    Write-Host ''
    Write-Host ("  ERRO: este teste precisa de um host STA (WinForms). Apartamento atual: " + $apartamento + '.') -ForegroundColor Red
    Write-Host '  Rode com o powershell.exe (Windows PowerShell 5.1), que e o padrao do README.' -ForegroundColor Red
    Write-Host ''
    exit 1
}

Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
Add-Type -AssemblyName System.Drawing -ErrorAction Stop

# ---------------------------------------------------------------------------
# P/Invoke do lado do teste (injetar input e forcar o foco da janela de teste)
# ---------------------------------------------------------------------------
Add-Type -Namespace RemapTeste -Name Win32 -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern void mouse_event(uint dwFlags, int dx, int dy, uint dwData, System.UIntPtr dwExtraInfo);

[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool SetCursorPos(int x, int y);

[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern System.IntPtr GetForegroundWindow();

[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool SetForegroundWindow(System.IntPtr hWnd);

[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern uint GetWindowThreadProcessId(System.IntPtr hWnd, System.IntPtr lpdwProcessId);

[System.Runtime.InteropServices.DllImport("kernel32.dll")]
public static extern uint GetCurrentThreadId();

[System.Runtime.InteropServices.DllImport("user32.dll")]
public static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);

// Truque padrao para furtar o foco: sem anexar a thread, o SetForegroundWindow
// costuma apenas piscar o icone na barra de tarefas.
public static bool ForcarFoco(System.IntPtr hWnd)
{
    if (hWnd == System.IntPtr.Zero) return false;
    if (GetForegroundWindow() == hWnd) return true;

    uint tidFoco = GetWindowThreadProcessId(GetForegroundWindow(), System.IntPtr.Zero);
    uint tidEu = GetCurrentThreadId();

    bool ok;
    if (tidFoco != 0 && tidFoco != tidEu)
    {
        AttachThreadInput(tidEu, tidFoco, true);
        ok = SetForegroundWindow(hWnd);
        AttachThreadInput(tidEu, tidFoco, false);
    }
    else
    {
        ok = SetForegroundWindow(hWnd);
    }
    return ok && GetForegroundWindow() == hWnd;
}
'@

$MOUSEEVENTF_LEFTDOWN   = 0x0002
$MOUSEEVENTF_LEFTUP     = 0x0004
$MOUSEEVENTF_MIDDLEDOWN = 0x0020
$MOUSEEVENTF_MIDDLEUP   = 0x0040
$MOUSEEVENTF_WHEEL      = 0x0800

$pasta       = $PSScriptRoot
$scriptRemap = Join-Path $pasta 'Remap-MiddleClickToCtrlF4.ps1'
if (-not (Test-Path -LiteralPath $scriptRemap)) {
    throw "Nao encontrei o script do remapeamento em: $scriptRemap"
}

$carimbo   = Get-Date -Format 'yyyyMMdd-HHmmss'
$logCadeia = Join-Path $env:TEMP "remap-teste-cadeia-$carimbo.log"
$logFim    = Join-Path $env:TEMP "remap-teste-encerramento-$carimbo.log"

$falhas     = New-Object 'System.Collections.Generic.List[string]'
$averbacoes = New-Object 'System.Collections.Generic.List[string]'
$processos  = New-Object 'System.Collections.Generic.List[System.Diagnostics.Process]'

function Esperar-Log {
    param(
        [string]$Caminho,
        [string]$Padrao,
        [int]$Segundos,
        [System.Diagnostics.Process]$Processo
    )
    $limite = (Get-Date).AddSeconds($Segundos)
    while ((Get-Date) -lt $limite) {
        if (Test-Path -LiteralPath $Caminho) {
            $texto = Get-Content -LiteralPath $Caminho -Raw -ErrorAction SilentlyContinue
            if ($texto -and $texto.Contains($Padrao)) { return $true }
        }
        if ($Processo -and $Processo.HasExited) { return $false }
        Start-Sleep -Milliseconds 250
    }
    return $false
}

function Iniciar-Remap {
    param([string[]]$Extras)
    $argumentos = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', $scriptRemap) + $Extras
    $linha = ($argumentos | ForEach-Object { '"' + $_ + '"' }) -join ' '
    return Start-Process -FilePath 'powershell.exe' -ArgumentList $linha -PassThru -WindowStyle Hidden
}

function Mostrar-Log {
    param([string]$Caminho, [string]$Titulo)
    Write-Host ""
    Write-Host "  --- $Titulo ---" -ForegroundColor DarkGray
    if (Test-Path -LiteralPath $Caminho) {
        Get-Content -LiteralPath $Caminho | ForEach-Object { Write-Host ("  " + $_) -ForegroundColor DarkGray }
    }
    else {
        Write-Host "  (arquivo de log inexistente)" -ForegroundColor DarkGray
    }
}

# Guarda a posicao do cursor para devolver no final.
$cursorOriginal = [System.Windows.Forms.Cursor]::Position

Write-Host ''
Write-Host '  Teste do remapeamento botao do meio -> CTRL+F4' -ForegroundColor Cyan
Write-Host '  ATENCAO: durante uns 15 segundos o botao do meio ficara remapeado no' -ForegroundColor Yellow
Write-Host '  sistema inteiro e o cursor sera movido. Nao mexa no mouse. A janela de' -ForegroundColor Yellow
Write-Host '  teste e um form vazio: nada nela pode ser fechado ou alterado.' -ForegroundColor Yellow
Write-Host ''

try {
    # =======================================================================
    # PARTE 1 - a cadeia completa
    # =======================================================================
    Write-Host '  [1/2] Cadeia completa (suprimir o meio + enviar CTRL+F4 + rolagem intacta)' -ForegroundColor Cyan

    $remap = Iniciar-Remap @('-LogFile', $logCadeia)
    [void]$processos.Add($remap)
    Write-Host ("        remapeamento subiu como PID " + $remap.Id) -ForegroundColor DarkGray

    if (-not (Esperar-Log -Caminho $logCadeia -Padrao 'hook WH_MOUSE_LL instalado' -Segundos 40 -Processo $remap)) {
        if ($remap.HasExited) {
            [void]$falhas.Add("O processo do remapeamento saiu sozinho (exit code $($remap.ExitCode)). Provavelmente ja existe um remapeamento rodando (mutex de instancia unica) ou o hook nao pode ser instalado. Rode Parar-Remap.cmd e tente de novo.")
        }
        else {
            [void]$falhas.Add('O hook nao foi instalado em 40 segundos (nenhuma linha "hook WH_MOUSE_LL instalado" no log).')
        }
        Mostrar-Log -Caminho $logCadeia -Titulo 'log do remapeamento'
    }
    else {
        Write-Host '        hook instalado' -ForegroundColor DarkGray

        $eventos = New-Object 'System.Collections.Generic.List[string]'
        $form = New-Object System.Windows.Forms.Form
        $form.Text            = 'Teste do remap - nao feche (fecha sozinho)'
        $form.KeyPreview      = $true
        $form.TopMost         = $true
        $form.StartPosition   = 'Manual'
        $form.Location        = [System.Drawing.Point]::new(140, 140)
        $form.Size            = [System.Drawing.Size]::new(460, 220)
        $form.BackColor       = [System.Drawing.Color]::FromArgb(245, 245, 210)

        $form.Add_KeyDown({ param($s, $e)
            if ($e.KeyCode -eq [System.Windows.Forms.Keys]::F4) {
                $script:eventos.Add('KEYDOWN F4 ctrl=' + $e.Control)
            }
        })
        $form.Add_MouseDown({ param($s, $e)
            $script:eventos.Add('MOUSEDOWN ' + $e.Button)
        })
        $form.Add_MouseWheel({ param($s, $e)
            $script:eventos.Add('WHEEL delta=' + $e.Delta)
        })

        $script:eventos     = $eventos
        $script:form        = $form
        $script:passo       = 0
        $script:injetado    = $false
        $script:comFoco     = $false
        $script:tentativas  = 0
        $script:esperaFinal = 0
        $script:estourou    = $false

        $timer = New-Object System.Windows.Forms.Timer
        $timer.Interval = 400

        $timer.Add_Tick({
            $script:passo++

            # Trava de seguranca: nunca deixa o teste pendurar.
            if ($script:passo -gt 90) {
                $script:estourou = $true
                $script:timer.Stop()
                $script:form.Close()
                return
            }

            try {
                if (-not $script:injetado) {
                    # 1) Focar a janela de teste (com o truque de AttachThreadInput).
                    if (-not [RemapTeste.Win32]::ForcarFoco($script:form.Handle)) {
                        $script:tentativas++
                        if ($script:tentativas -lt 20) { return }
                        # Nao conseguiu o foco: segue assim mesmo e a checagem de
                        # entrega do CTRL+F4 sera reportada como inconclusiva.
                    }
                    else {
                        $script:comFoco = $true
                    }

                    # 2) Cursor para o meio da janela, para que rolagem e clique
                    #    esquerdo cheguem nela.
                    $meio = [System.Drawing.Point]::new(
                        [int]($script:form.ClientSize.Width / 2),
                        [int]($script:form.ClientSize.Height / 2))
                    $alvo = $script:form.PointToScreen($meio)
                    [void][RemapTeste.Win32]::SetCursorPos($alvo.X, $alvo.Y)
                    Start-Sleep -Milliseconds 250

                    # 3) O clique do meio: deve ser suprimido e virar CTRL+F4.
                    [RemapTeste.Win32]::mouse_event($script:MOUSEEVENTF_MIDDLEDOWN, 0, 0, 0, [System.UIntPtr]::Zero)
                    Start-Sleep -Milliseconds 60
                    [RemapTeste.Win32]::mouse_event($script:MOUSEEVENTF_MIDDLEUP, 0, 0, 0, [System.UIntPtr]::Zero)
                    Start-Sleep -Milliseconds 400

                    # 4) A rolagem: deve continuar passando.
                    [RemapTeste.Win32]::mouse_event($script:MOUSEEVENTF_WHEEL, 0, 0, 120, [System.UIntPtr]::Zero)
                    Start-Sleep -Milliseconds 250

                    # 5) O botao esquerdo: deve continuar passando.
                    [RemapTeste.Win32]::mouse_event($script:MOUSEEVENTF_LEFTDOWN, 0, 0, 0, [System.UIntPtr]::Zero)
                    Start-Sleep -Milliseconds 60
                    [RemapTeste.Win32]::mouse_event($script:MOUSEEVENTF_LEFTUP, 0, 0, 0, [System.UIntPtr]::Zero)

                    $script:injetado = $true
                    return
                }

                # 6) Deixa os eventos assentarem e fecha.
                $script:esperaFinal++
                if ($script:esperaFinal -ge 4) {
                    $script:timer.Stop()
                    $script:form.Close()
                }
            }
            catch {
                $script:eventos.Add('ERRO NO PROPRIO TESTE: ' + $_.Exception.Message)
                $script:timer.Stop()
                $script:form.Close()
            }
        })

        $script:timer = $timer
        $timer.Start()

        [void][System.Windows.Forms.Application]::Run($form)
        $timer.Dispose()

        $texto = $script:eventos -join ' | '

        if ($script:estourou) {
            [void]$falhas.Add('A janela de teste estourou o tempo limite sem completar os passos (o foco nunca foi obtido?).')
        }

        # 1. O clique do meio foi suprimido?
        if ($texto -match 'MOUSEDOWN Middle') {
            [void]$falhas.Add('O clique do meio CHEGOU na janela: nao foi suprimido.')
        }
        else {
            Write-Host '        OK: o clique do meio nao chegou na janela (suprimido)' -ForegroundColor Green
        }

        # 2. O CTRL+F4 chegou?
        if ($texto -match 'KEYDOWN F4 ctrl=True') {
            Write-Host '        OK: o CTRL+F4 chegou na janela (atalho enviado)' -ForegroundColor Green
        }
        elseif ($script:comFoco) {
            [void]$falhas.Add('O CTRL+F4 NAO chegou na janela de teste (com a janela em foco).')
        }
        else {
            [void]$averbacoes.Add('Nao consegui dar foco a janela de teste, entao a entrega do CTRL+F4 ficou inconclusiva.')
        }

        # 3. A rolagem continuou passando?
        if ($texto -match 'WHEEL delta=120') {
            Write-Host '        OK: a rolagem continuou chegando na janela (intacta)' -ForegroundColor Green
        }
        else {
            [void]$falhas.Add('A rolagem NAO chegou na janela de teste: o hook pode estar engolindo WM_MOUSEWHEEL.')
        }

        # 4. O botao esquerdo continuou passando?
        if ($texto -match 'MOUSEDOWN Left') {
            Write-Host '        OK: o botao esquerdo continuou chegando (intacto)' -ForegroundColor Green
        }
        else {
            [void]$falhas.Add('O botao esquerdo NAO chegou na janela de teste.')
        }

        # 5. O remapeamento registrou o envio de 4/4 eventos?
        $logTexto = Get-Content -LiteralPath $logCadeia -Raw -ErrorAction SilentlyContinue
        if ($logTexto -and $logTexto.Contains('SendInput retornou 4/4 eventos')) {
            Write-Host '        OK: SendInput aceitou os 4 eventos do CTRL+F4' -ForegroundColor Green
        }
        else {
            [void]$falhas.Add('O log nao registrou "SendInput retornou 4/4 eventos" (envio bloqueado pelo UIPI ou nao realizado).')
        }
        if ($logTexto -and $logTexto.Contains('clique do meio detectado -> enviando CTRL+F4')) {
            Write-Host '        OK: o hook registrou o clique do meio' -ForegroundColor Green
        }
        else {
            [void]$falhas.Add('O log nao registrou a deteccao do clique do meio.')
        }

        Write-Host ("        eventos capturados: " + $texto) -ForegroundColor DarkGray
    }

    # Mata o remapeamento da parte 1 (morte brusca: tambem serve para provar que
    # o sistema libera o hook e que a proxima instancia lida com o mutex abandonado).
    if (-not $remap.HasExited) {
        $remap.Kill()
        $remap.WaitForExit(5000) | Out-Null
    }
    Write-Host ''

    # =======================================================================
    # PARTE 2 - encerramento limpo por tempo
    # =======================================================================
    Write-Host '  [2/2] Encerramento limpo (-MaxSeconds) e recuperacao do mutex' -ForegroundColor Cyan

    $remap2 = Iniciar-Remap @('-MaxSeconds', '6', '-LogFile', $logFim)
    [void]$processos.Add($remap2)
    Write-Host ("        remapeamento subiu como PID " + $remap2.Id) -ForegroundColor DarkGray

    if (-not (Esperar-Log -Caminho $logFim -Padrao 'hook WH_MOUSE_LL instalado' -Segundos 40 -Processo $remap2)) {
        [void]$falhas.Add('A segunda instancia nao instalou o hook: a recuperacao do mutex abandonado (apos morte brusca) falhou.')
        Mostrar-Log -Caminho $logFim -Titulo 'log da segunda instancia'
    }
    else {
        Write-Host '        hook instalado de novo (mutex abandonado foi recuperado)' -ForegroundColor Green

        $saiuSozinho = $remap2.WaitForExit(30000)
        if (-not $saiuSozinho) {
            [void]$falhas.Add('O processo nao saiu sozinho depois de -MaxSeconds 6.')
        }
        else {
            Write-Host '        o processo saiu sozinho no tempo previsto' -ForegroundColor Green
        }

        if (Test-Path -LiteralPath $logFim) {
            $textoFim = Get-Content -LiteralPath $logFim -Raw -ErrorAction SilentlyContinue
            if ($textoFim -and $textoFim.Contains('hook WH_MOUSE_LL removido')) {
                Write-Host '        OK: o hook foi desinstalado (UnhookWindowsHookEx) no encerramento' -ForegroundColor Green
            }
            else {
                [void]$falhas.Add('O log nao registrou "hook WH_MOUSE_LL removido": o encerramento nao desinstalou o hook.')
            }
        }
        else {
            [void]$falhas.Add('A segunda instancia nao gerou log.')
        }
    }
}
finally {
    foreach ($p in $processos) {
        try {
            if (-not $p.HasExited) {
                $p.Kill()
                $p.WaitForExit(5000) | Out-Null
            }
        }
        catch { }
        try { $p.Dispose() } catch { }
    }

    # Devolve o cursor para onde estava.
    try { [void][RemapTeste.Win32]::SetCursorPos($cursorOriginal.X, $cursorOriginal.Y) } catch { }

    if (-not $KeepLog) {
        foreach ($caminho in @($logCadeia, $logFim)) {
            try { if (Test-Path -LiteralPath $caminho) { Remove-Item -LiteralPath $caminho -Force } } catch { }
        }
    }
}

# ---------------------------------------------------------------------------
# Veredito
# ---------------------------------------------------------------------------
Write-Host ''
foreach ($a in $averbacoes) {
    Write-Host ("  AVISO: " + $a) -ForegroundColor Yellow
}

if ($falhas.Count -eq 0) {
    Write-Host '  RESULTADO: PASSOU' -ForegroundColor Green
    Write-Host ''
    exit 0
}

Write-Host ("  RESULTADO: FALHOU (" + $falhas.Count + " problema(s))") -ForegroundColor Red
foreach ($f in $falhas) {
    Write-Host ("    - " + $f) -ForegroundColor Red
}
if (-not $KeepLog) {
    Write-Host '  (rode com -KeepLog para guardar os logs do teste)' -ForegroundColor DarkGray
}
Write-Host ''
exit 1
