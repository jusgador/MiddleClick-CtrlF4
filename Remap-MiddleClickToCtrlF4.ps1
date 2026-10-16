#Requires -Version 5.1
<#
.SYNOPSIS
    Remapeia o botao do meio do mouse para o atalho CTRL+F4, globalmente.

.DESCRIPTION
    Instala um hook de mouse de baixo nivel (WH_MOUSE_LL) via P/Invoke, sem nenhuma
    dependencia externa: roda em qualquer Windows com o powershell.exe nativo.

    Comportamento:
      - O CLIQUE do botao do meio (WM_MBUTTONDOWN / WM_MBUTTONUP / WM_MBUTTONDBLCLK)
        e' suprimido e substituido por CTRL+F4. O "autoscroll" (a cruzinha que aparece
        ao apertar a roda) e' disparado pelo CLIQUE, entao ele sai de cena junto.
      - A ROLAGEM vertical (WM_MOUSEWHEEL, 0x020A) ganha ACELERACAO: o evento original
        sempre passa intacto e na hora; quando os degraus da roda chegam em sequencia
        rapida (girando continuamente), o script injeta um evento EXTRA com a diferenca
        (fator 2x, 3x... ate o maximo). Girando devagar, nada muda. Desligue com
        -NoScrollAccel. A rolagem horizontal (WM_MOUSEHWHEEL) nao e' tocada.
      - O BOTAO PEQUENO abaixo da roda (Logitech M535 por Bluetooth), que de fabrica
        manda Win+Tab, passa a enviar ALT+F4 (ou o atalho de -SmallButtonKeys). Isso
        e' feito pedindo ao proprio mouse, pelo protocolo HID++ da Logitech, que desvie
        o botao para este script. No encerramento limpo o botao volta ao normal.
        Desligue com -NoSmallButton.
      - Botoes esquerdo/direito e botoes laterais (XBUTTON) nao sao afetados.

    Detalhe de implementacao importante: o SendInput NAO e' chamado dentro do callback
    do hook. O callback apenas marca o evento e joga o envio para o ThreadPool. Se o
    callback demorar mais que o LowLevelHooksTimeout do Windows (300 ms por padrao), o
    proprio Windows desinstala o hook silenciosamente.

.PARAMETER TriggerOn
    Em qual evento do botao do meio o CTRL+F4 e' enviado: 'Down' (padrao) ou 'Up'.
    Nos dois casos o clique inteiro (down e up) e' suprimido.

.PARAMETER DryRun
    Faz tudo igual ao modo real -- inclusive suprimir o clique do meio -- mas NAO
    envia o CTRL+F4. Serve para diagnosticar/testar sem disparar o atalho de verdade.

.PARAMETER LogFile
    Caminho de um arquivo onde cada evento e' registrado. Padrao: nenhum log.

.PARAMETER NoSwallow
    Modo diagnostico: envia o CTRL+F4 mas deixa o clique do meio passar tambem.
    Em navegador isso significa "abrir link em nova aba" E o CTRL+F4 ao mesmo tempo.

.PARAMETER MiddleClickKeys
    Atalho enviado pelo clique do botao do meio. Padrao 'CTRL+F4'. Mesmo formato de
    -SmallButtonKeys.

.PARAMETER NoMiddleClick
    Nao mexe no clique do botao do meio (ele volta ao normal).

.PARAMETER OnlyProcess
    Restringe o remapeamento a um unico programa (nome do processo, com ou sem .exe,
    ex.: 'pje1g'). Nos demais programas o clique do meio funciona normalmente.
    Desligado por padrao -- sem este parametro o remapeamento e' GLOBAL.

.PARAMETER HoldMilliseconds
    Pausa entre o "aperta" e o "solta" do CTRL+F4. Padrao 0 (envio atomico).
    Aumente para 30-50 apenas se algum programa reclamar que perdeu o atalho.

.PARAMETER MaxSeconds
    Encerra sozinho depois de N segundos (0 = fica rodando ate voce parar).
    Util para remapear so por um tempo, e usado pelos testes para exercitar
    o encerramento limpo (unhook) de forma automatizada.

.PARAMETER NoScrollAccel
    Desliga a aceleracao da rolagem (a roda volta a passar 100% intocada).

.PARAMETER ScrollFastMs
    Intervalo maximo, em ms, entre dois degraus da roda (no mesmo sentido) para
    contarem como "giro continuo". Padrao 80. Maior = acelera com giros mais lentos.

.PARAMETER ScrollRampNotches
    Quantos degraus rapidos seguidos sobem o fator em +1. Padrao 2.
    Menor = acelera mais cedo; maior = acelera mais aos poucos.

.PARAMETER ScrollMaxFactor
    Fator maximo da aceleracao (1 = sem aceleracao). Padrao 5.

.PARAMETER ScrollAccelInjected
    Diagnostico/teste: acelera tambem rolagens INJETADAS por outros programas. Por
    padrao elas sao ignoradas, para nao multiplicar a rolagem suave de softwares de
    mouse (Logitech etc.) que injetam muitos eventos pequenos. Os testes usam isto.

.PARAMETER SmallButtonKeys
    Atalho enviado pelo BOTAO PEQUENO abaixo da roda (Logitech M535 e parecidos,
    via Bluetooth). Padrao 'ALT+F4'. Teclas separadas por '+': modificadores CTRL,
    ALT, SHIFT, WIN; letras A-Z; digitos 0-9; F1-F24; ENTER, ESC, TAB, SPACE,
    BACKSPACE, DELETE, INSERT, HOME, END, PGUP, PGDN, UP, DOWN, LEFT, RIGHT;
    midia PLAYPAUSE, NEXTTRACK, PREVTRACK, STOP, MUTE, VOLUP, VOLDOWN.
    Ex.: 'CTRL+W', 'CTRL+SHIFT+T', 'WIN+D', 'PLAYPAUSE'.
    ALT+F4 e' enviado como o comando "Fechar" da janela em foco (WM_SYSCOMMAND /
    SC_CLOSE), que funciona ate' em apps que ignoram o ALT simulado.

.PARAMETER NoSmallButton
    Nao mexe no botao pequeno: ele continua abrindo a Visao de Tarefas (Win+Tab).

.PARAMETER SmallButtonCid
    Avancado: o "control ID" HID++ do botao pequeno. Padrao 0x00D0 (o do M535).

.PARAMETER IgnoreConfig
    Ignora o arquivo de configuracao (%APPDATA%\MiddleClick-CtrlF4\config.json) e
    usa so' os padroes e os parametros. Os testes usam isto.

.PARAMETER NoTray
    Nao mostra o icone na bandeja (nem a janela de configuracoes).

.EXAMPLE
    .\Remap-MiddleClickToCtrlF4.ps1
    Remapeamento global, em primeiro plano. Pare com Ctrl+C.

.EXAMPLE
    .\Remap-MiddleClickToCtrlF4.ps1 -SmallButtonKeys 'CTRL+W'
    O botao pequeno abaixo da roda passa a fechar a aba (CTRL+W).

.EXAMPLE
    .\Remap-MiddleClickToCtrlF4.ps1 -ScrollMaxFactor 8 -ScrollRampNotches 1
    Aceleracao mais agressiva da rolagem.

.EXAMPLE
    .\Remap-MiddleClickToCtrlF4.ps1 -OnlyProcess pje1g
    Somente no programa pje1g.exe.

.EXAMPLE
    .\Remap-MiddleClickToCtrlF4.ps1 -DryRun -LogFile "$env:TEMP\remap.log"
    Testa o hook sem enviar o atalho, registrando tudo no log.

.NOTES
    CONFIGURACAO: os valores vem, nesta ordem de prioridade, dos parametros passados
    na linha de comando, do arquivo %APPDATA%\MiddleClick-CtrlF4\config.json (gravado
    pela janela de configuracoes) e dos padroes acima. A janela abre clicando no icone
    da bandeja, ou rodando o script (ou o Iniciar-Remap.vbs) de novo com ele ja ativo.

    Projeto: D:\dev\MiddleClick-CtrlF4
    Requer: Windows + Windows PowerShell 5.1 (ou PowerShell 7). Nada para instalar.
#>
[CmdletBinding()]
param(
    [ValidateSet('Down', 'Up')]
    [string]$TriggerOn = 'Down',

    [switch]$DryRun,

    [string]$LogFile,

    [switch]$NoSwallow,

    [string]$MiddleClickKeys = 'CTRL+F4',

    [switch]$NoMiddleClick,

    [string]$OnlyProcess,

    [int]$HoldMilliseconds = 0,

    [int]$MaxSeconds = 0,

    [switch]$NoScrollAccel,

    [ValidateRange(1, 1000)]
    [int]$ScrollFastMs = 80,

    [ValidateRange(1, 100)]
    [int]$ScrollRampNotches = 2,

    [ValidateRange(1, 50)]
    [int]$ScrollMaxFactor = 5,

    [switch]$ScrollAccelInjected,

    [string]$SmallButtonKeys = 'ALT+F4',

    [switch]$NoSmallButton,

    [ValidateRange(1, 0xFFFF)]
    [int]$SmallButtonCid = 0x00D0,

    [switch]$IgnoreConfig,

    [switch]$NoTray
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Instancia unica: duas copias rodando nao fazem sentido (o primeiro hook da
# cadeia ja suprime o evento antes do segundo ver qualquer coisa).
# ---------------------------------------------------------------------------
$mutex = New-Object System.Threading.Mutex($false, 'Local\MiddleClick-CtrlF4')
$adquiriu = $false
try {
    $adquiriu = $mutex.WaitOne(0)
}
catch [System.Threading.AbandonedMutexException] {
    # O titular anterior morreu sem liberar o mutex (ex.: Stop-Process -Force).
    # Nesse caso o mutex e' nosso.
    $adquiriu = $true
}

if (-not $adquiriu) {
    # Ja tem um rodando: pede a ele que abra a janela de configuracoes.
    $pediu = $false
    try {
        $evento = [System.Threading.EventWaitHandle]::OpenExisting('Local\MiddleClick-CtrlF4-Configurar')
        [void]$evento.Set()
        $evento.Dispose()
        $pediu = $true
    }
    catch { }
    if ($pediu) { Write-Host 'O remapeamento ja esta em execucao: abrindo a janela de configuracoes dele.' }
    else { Write-Warning 'O remapeamento ja esta em execucao nesta sessao. Nada a fazer.' }
    $mutex.Dispose()
    exit 0
}

# ---------------------------------------------------------------------------
# Núcleo em C#. Sintaxe compativel com C# 5 de proposito, para o mesmo texto
# compilar no Add-Type do Windows PowerShell 5.1 e no do PowerShell 7.
# ---------------------------------------------------------------------------
$codigoCSharp = @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;
using Microsoft.Win32.SafeHandles;

public static class MiddleClickRemap
{
    // ---- Constantes Win32 ----
    private const int WH_MOUSE_LL = 14;

    private const int WM_MBUTTONDOWN    = 0x0207;
    private const int WM_MBUTTONUP      = 0x0208;
    private const int WM_MBUTTONDBLCLK  = 0x0209;
    private const int WM_MOUSEWHEEL     = 0x020A;

    private const uint LLMHF_INJECTED   = 0x00000001;
    private const uint INPUT_MOUSE      = 0;
    private const uint MOUSEEVENTF_WHEEL = 0x0800;

    // Marca gravada no dwExtraInfo da rolagem extra que nos mesmos injetamos,
    // para o hook reconhece-la e nao acelera-la de novo (loop).
    private static readonly IntPtr MARCA_ROLAGEM_PROPRIA = new IntPtr(0x4D435743);   // "MCWC"

    private const uint WM_QUIT     = 0x0012;
    private const uint PM_NOREMOVE = 0x0000;

    private const uint INPUT_KEYBOARD  = 1;
    private const uint KEYEVENTF_KEYUP = 0x0002;
    private const uint KEYEVENTF_EXTENDEDKEY = 0x0001;
    private const ushort VK_CONTROL    = 0x11;
    private const ushort VK_F4         = 0x73;

    // ---- Estruturas Win32 ----
    [StructLayout(LayoutKind.Sequential)]
    private struct POINT
    {
        public int x;
        public int y;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MSLLHOOKSTRUCT
    {
        public POINT pt;
        public uint mouseData;
        public uint flags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MSG
    {
        public IntPtr hwnd;
        public uint message;
        public IntPtr wParam;
        public IntPtr lParam;
        public uint time;
        public POINT pt;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MOUSEINPUT
    {
        public int dx;
        public int dy;
        public uint mouseData;
        public uint dwFlags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct KEYBDINPUT
    {
        public ushort wVk;
        public ushort wScan;
        public uint dwFlags;
        public uint time;
        public IntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct HARDWAREINPUT
    {
        public uint uMsg;
        public ushort wParamL;
        public ushort wParamH;
    }

    [StructLayout(LayoutKind.Explicit)]
    private struct InputUnion
    {
        [FieldOffset(0)] public MOUSEINPUT mi;
        [FieldOffset(0)] public KEYBDINPUT ki;
        [FieldOffset(0)] public HARDWAREINPUT hi;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct INPUT
    {
        public uint type;
        public InputUnion u;
    }

    private delegate IntPtr LowLevelMouseProc(int nCode, IntPtr wParam, IntPtr lParam);

    // ---- P/Invoke ----
    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr SetWindowsHookEx(int idHook, LowLevelMouseProc lpfn, IntPtr hMod, uint dwThreadId);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool UnhookWindowsHookEx(IntPtr hhk);

    [DllImport("user32.dll")]
    private static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);

    private const uint MAPVK_VK_TO_VSC = 0;
    private const uint WM_SYSCOMMAND = 0x0112;
    private const int SC_CLOSE = 0xF060;

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool PostMessage(IntPtr hWnd, uint msg, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern uint MapVirtualKey(uint uCode, uint uMapType);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool PeekMessage(out MSG lpMsg, IntPtr hWnd, uint wMsgFilterMin, uint wMsgFilterMax, uint wRemoveMsg);

    // Loop BLOQUEANTE de proposito: e' o unico jeito de o Windows entregar o
    // callback do hook sem atrasar o input do sistema inteiro.
    [DllImport("user32.dll")]
    private static extern int GetMessage(out MSG lpMsg, IntPtr hWnd, uint wMsgFilterMin, uint wMsgFilterMax);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool TranslateMessage(ref MSG lpMsg);

    [DllImport("user32.dll")]
    private static extern IntPtr DispatchMessage(ref MSG lpMsg);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool PostThreadMessage(uint idThread, uint msg, IntPtr wParam, IntPtr lParam);

    [DllImport("kernel32.dll")]
    private static extern uint GetCurrentThreadId();

    [DllImport("kernel32.dll", CharSet = CharSet.Auto)]
    private static extern IntPtr GetModuleHandle(string lpModuleName);

    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

    // ---- Estado ----
    private static readonly object _sync = new object();

    private static LowLevelMouseProc _proc;          // raiz forte: sem isso o GC coleta o delegate e o callback quebra
    private static IntPtr _hook = IntPtr.Zero;
    private static Thread _thread;
    private static uint _threadId;
    private static volatile bool _running;
    private static ManualResetEvent _ready = new ManualResetEvent(false);
    private static string _installError;

    private static bool _dryRun;
    private static bool _swallow = true;
    // Configuracao do clique do meio: pode mudar com o hook rodando (janela de
    // configuracoes, pausa), por isso volatil e lida uma vez por evento.
    private static volatile string _onlyProcess;
    private static volatile bool _meioAtivo = true;
    private static volatile ushort[] _teclasMeio = new ushort[] { VK_CONTROL, VK_F4 };
    private static volatile string _nomeMeio = "CTRL+F4";
    private static bool _triggerOnDown = true;
    private static int _holdMs;

    private static bool _rolagemAcelerada;
    private static uint _rolagemRapidaMs;
    private static int _rolagemDegrausPorPasso;
    private static int _rolagemFatorMaximo;
    private static bool _rolagemAceleraInjetada;

    // Estado da aceleracao: so e' tocado pela thread do hook.
    private static bool _temRodaAnterior;
    private static uint _ultimoTempoRoda;
    private static int _ultimoSinalRoda;
    private static int _sequenciaRapida;

    private static StreamWriter _log;

    private static long _cliquesSuprimidos;
    private static long _ctrlF4Enviados;
    private static long _rolagensAceleradas;

    private static int _ultimoPid;
    private static bool _ultimoPidCasa;

    public static long MiddleClicksSuppressed
    {
        get { return Interlocked.Read(ref _cliquesSuprimidos); }
    }

    public static long CtrlF4Sent
    {
        get { return Interlocked.Read(ref _ctrlF4Enviados); }
    }

    public static long WheelEventsAccelerated
    {
        get { return Interlocked.Read(ref _rolagensAceleradas); }
    }

    // -------------------------------------------------------------------
    // API publica
    // -------------------------------------------------------------------
    public static void ConfigureScrollAccel(bool enabled, int fastMs, int rampNotches, int maxFactor, bool accelerateInjected)
    {
        _rolagemAcelerada = enabled && maxFactor > 1;
        _rolagemRapidaMs = (uint)(fastMs < 1 ? 1 : fastMs);
        _rolagemDegrausPorPasso = rampNotches < 1 ? 1 : rampNotches;
        _rolagemFatorMaximo = maxFactor < 1 ? 1 : maxFactor;
        _rolagemAceleraInjetada = accelerateInjected;
        _temRodaAnterior = false;
        _sequenciaRapida = 0;

        Log(_rolagemAcelerada
            ? "aceleracao da rolagem: ligada (" + _rolagemRapidaMs.ToString() + " ms, +1x a cada " +
              _rolagemDegrausPorPasso.ToString() + " degraus, maximo " + _rolagemFatorMaximo.ToString() + "x" +
              (_rolagemAceleraInjetada ? ", inclusive rolagem injetada" : "") + ")."
            : "aceleracao da rolagem: desligada.");
    }

    public static void ConfigureMiddleClick(bool enabled, ushort[] keys, string keysName, string onlyProcess)
    {
        _teclasMeio = (keys != null && keys.Length > 0) ? keys : new ushort[] { VK_CONTROL, VK_F4 };
        _nomeMeio = string.IsNullOrEmpty(keysName) ? "CTRL+F4" : keysName;
        _onlyProcess = string.IsNullOrEmpty(onlyProcess) ? null : NormalizeProcess(onlyProcess);
        _ultimoPid = 0;   // invalida o cache do filtro por programa
        _meioAtivo = enabled;

        Log(enabled
            ? "clique do meio: ligado -> " + _nomeMeio + (_onlyProcess != null ? " (so' em " + _onlyProcess + ")" : "") + "."
            : "clique do meio: desligado (passa normal).");
    }

    public static void Start(string logFile, bool dryRun, bool swallow, string triggerOn, int holdMilliseconds)
    {
        if (_running)
        {
            throw new InvalidOperationException("O remapeamento ja esta em execucao.");
        }

        _dryRun = dryRun;
        _swallow = swallow;
        _triggerOnDown = !string.Equals(triggerOn, "Up", StringComparison.OrdinalIgnoreCase);
        _holdMs = holdMilliseconds < 0 ? 0 : holdMilliseconds;

        if (!string.IsNullOrEmpty(logFile))
        {
            string caminho = Path.GetFullPath(logFile);
            string pasta = Path.GetDirectoryName(caminho);
            if (!string.IsNullOrEmpty(pasta)) Directory.CreateDirectory(pasta);
            _log = new StreamWriter(new FileStream(caminho, FileMode.Append, FileAccess.Write, FileShare.ReadWrite));
            _log.AutoFlush = true;
        }

        _ready = new ManualResetEvent(false);
        _installError = null;
        _cliquesSuprimidos = 0;
        _ctrlF4Enviados = 0;
        _rolagensAceleradas = 0;

        _running = true;
        _thread = new Thread(ThreadMain);
        _thread.IsBackground = true;
        _thread.Name = "MiddleClickRemapHook";
        _thread.Start();

        if (!_ready.WaitOne(10000))
        {
            TryStop();
            throw new InvalidOperationException("Timeout ao instalar o hook de mouse.");
        }

        if (_installError != null)
        {
            string erro = _installError;
            TryStop();
            throw new InvalidOperationException(erro);
        }
    }

    public static void Stop()
    {
        _running = false;

        if (_thread != null)
        {
            uint tid = _threadId;
            if (tid != 0)
            {
                // Acorda o GetMessage bloqueante para a thread encerrar o loop.
                PostThreadMessage(tid, WM_QUIT, IntPtr.Zero, IntPtr.Zero);
            }
            try { _thread.Join(3000); } catch { }
            _thread = null;
        }

        if (_hook != IntPtr.Zero)
        {
            UnhookWindowsHookEx(_hook);
            _hook = IntPtr.Zero;
        }

        _proc = null;
        _threadId = 0;

        lock (_sync)
        {
            if (_log != null)
            {
                try { _log.Flush(); _log.Dispose(); } catch { }
                _log = null;
            }
        }
    }

    // -------------------------------------------------------------------
    // Thread do hook + loop de mensagens
    // -------------------------------------------------------------------
    private static void ThreadMain()
    {
        try
        {
            // Cria a fila de mensagens desta thread antes de qualquer coisa:
            // o PostThreadMessage do Stop() so funciona se a fila existir.
            MSG ignorada;
            PeekMessage(out ignorada, IntPtr.Zero, 0, 0, PM_NOREMOVE);
            _threadId = GetCurrentThreadId();

            _proc = HookProc;
            _hook = SetWindowsHookEx(WH_MOUSE_LL, _proc, GetModuleHandle(null), 0);

            if (_hook == IntPtr.Zero)
            {
                int codigo = Marshal.GetLastWin32Error();
                _installError = "SetWindowsHookEx falhou (Win32 erro " + codigo.ToString() + ").";
                return;
            }

            Log("hook WH_MOUSE_LL instalado (thread " + _threadId.ToString() + ").");
            _ready.Set();

            MSG msg;
            while (_running)
            {
                int resultado = GetMessage(out msg, IntPtr.Zero, 0, 0);
                if (resultado <= 0) break;   // 0 = WM_QUIT, -1 = erro
                TranslateMessage(ref msg);
                DispatchMessage(ref msg);
            }
        }
        catch (Exception ex)
        {
            _installError = ex.Message;
        }
        finally
        {
            if (_hook != IntPtr.Zero)
            {
                UnhookWindowsHookEx(_hook);
                _hook = IntPtr.Zero;
            }
            Log("hook WH_MOUSE_LL removido.");
            _ready.Set();
        }
    }

    private static void TryStop()
    {
        try { Stop(); } catch { }
    }

    // -------------------------------------------------------------------
    // Callback do hook. Tem que ser curto: nada de I/O pesado, e o envio
    // do atalho vai para outra thread.
    // -------------------------------------------------------------------
    private static IntPtr HookProc(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode < 0)
        {
            return CallNextHookEx(_hook, nCode, wParam, lParam);
        }

        try
        {
            int mensagem = wParam.ToInt32();

            // So' anota o horario: o mouse voltando a mexer depois de um tempo
            // parado pode ter acordado e perdido o desvio do botao pequeno.
            LogiSmallButton.NotarAtividade();

            // Rolagem: o evento original SEMPRE segue intacto e sem atraso; no
            // maximo agendamos um evento extra para acelerar.
            if (mensagem == WM_MOUSEWHEEL)
            {
                if (_rolagemAcelerada)
                {
                    TratarRoda(lParam);
                }
                return CallNextHookEx(_hook, nCode, wParam, lParam);
            }

            bool ehDown = (mensagem == WM_MBUTTONDOWN) || (mensagem == WM_MBUTTONDBLCLK);
            bool ehUp = (mensagem == WM_MBUTTONUP);

            // Qualquer outra coisa (rolagem, botoes esquerdo/direito/laterais)
            // segue direto para o resto da cadeia, intocada.
            if (!ehDown && !ehUp)
            {
                return CallNextHookEx(_hook, nCode, wParam, lParam);
            }

            // Funcao desligada (configuracoes ou pausa): o clique do meio volta ao normal.
            if (!_meioAtivo)
            {
                return CallNextHookEx(_hook, nCode, wParam, lParam);
            }

            string soPrograma = _onlyProcess;
            if (soPrograma != null && !PrimeiroPlanoCasa(soPrograma))
            {
                return CallNextHookEx(_hook, nCode, wParam, lParam);
            }

            Interlocked.Increment(ref _cliquesSuprimidos);

            bool dispara = (_triggerOnDown && ehDown) || (!_triggerOnDown && ehUp);
            if (dispara)
            {
                ushort[] teclas = _teclasMeio;
                string nome = _nomeMeio;
                if (_dryRun)
                {
                    Log("clique do meio detectado -> DRY-RUN: enviaria " + nome + " (nao enviado).");
                }
                else
                {
                    Log("clique do meio detectado -> enviando " + nome + ".");
                    ThreadPool.QueueUserWorkItem(SendWorker, new object[] { teclas, nome });
                }
            }

            if (!_swallow)
            {
                return CallNextHookEx(_hook, nCode, wParam, lParam);
            }

            return new IntPtr(1);   // suprimido
        }
        catch (Exception ex)
        {
            try { Log("erro no callback do hook: " + ex.Message); } catch { }
            return CallNextHookEx(_hook, nCode, wParam, lParam);
        }
    }

    // -------------------------------------------------------------------
    // Aceleracao da rolagem. Roda dentro do callback: so contas, nada de I/O.
    // -------------------------------------------------------------------
    private static void TratarRoda(IntPtr lParam)
    {
        MSLLHOOKSTRUCT dados = (MSLLHOOKSTRUCT)Marshal.PtrToStructure(lParam, typeof(MSLLHOOKSTRUCT));

        // A rolagem extra que nos mesmos injetamos: deixa passar sem contar.
        if (dados.dwExtraInfo == MARCA_ROLAGEM_PROPRIA) return;

        // Rolagem injetada por outro programa (ex.: rolagem suave de software de
        // mouse): por padrao nao mexemos.
        if ((dados.flags & LLMHF_INJECTED) != 0 && !_rolagemAceleraInjetada) return;

        int delta = unchecked((short)(dados.mouseData >> 16));
        if (delta == 0) return;

        int sinal = delta > 0 ? 1 : -1;
        uint agora = dados.time != 0 ? dados.time : unchecked((uint)Environment.TickCount);

        bool rapido = false;
        if (_temRodaAnterior && sinal == _ultimoSinalRoda)
        {
            uint intervalo = unchecked(agora - _ultimoTempoRoda);   // sobrevive ao wrap do tick
            rapido = intervalo <= _rolagemRapidaMs;
        }

        _temRodaAnterior = true;
        _ultimoTempoRoda = agora;
        _ultimoSinalRoda = sinal;

        int teto = _rolagemFatorMaximo * _rolagemDegrausPorPasso;
        _sequenciaRapida = rapido ? Math.Min(_sequenciaRapida + 1, teto) : 0;

        int fator = Math.Min(1 + _sequenciaRapida / _rolagemDegrausPorPasso, _rolagemFatorMaximo);
        if (fator <= 1) return;

        // O delta da roda e' um short: limita o extra para nao estourar.
        int extra = delta * (fator - 1);
        if (extra > 30000) extra = 30000;
        if (extra < -30000) extra = -30000;

        Interlocked.Increment(ref _rolagensAceleradas);
        ThreadPool.QueueUserWorkItem(RolagemWorker, new int[] { extra, fator });
    }

    // Roda no ThreadPool: fora do callback do hook.
    private static void RolagemWorker(object state)
    {
        try
        {
            int[] dados = (int[])state;
            int extra = dados[0];

            INPUT[] entrada = new INPUT[1];
            entrada[0].type = INPUT_MOUSE;
            entrada[0].u.mi.mouseData = unchecked((uint)extra);
            entrada[0].u.mi.dwFlags = MOUSEEVENTF_WHEEL;
            entrada[0].u.mi.dwExtraInfo = MARCA_ROLAGEM_PROPRIA;

            uint enviados = SendInput(1, entrada, Marshal.SizeOf(typeof(INPUT)));
            Log("rolagem acelerada: fator " + dados[1].ToString() + ", extra " + extra.ToString() +
                " (SendInput " + enviados.ToString() + "/1).");
        }
        catch (Exception ex)
        {
            Log("falha ao enviar a rolagem extra: " + ex.Message);
        }
    }

    // Roda no ThreadPool: fora do callback do hook.
    private static void SendWorker(object state)
    {
        object[] dados = (object[])state;
        if (EnviarAtalho((ushort[])dados[0], (string)dados[1]))
        {
            Interlocked.Increment(ref _ctrlF4Enviados);
        }
    }

    // Envia o atalho para a janela em primeiro plano e registra no log. Usado pelo
    // clique do meio e pelo botao pequeno. Fora do callback do hook, sempre.
    internal static bool EnviarAtalho(ushort[] teclas, string nome)
    {
        try
        {
            string alvo = DescreverPrimeiroPlano();
            if (teclas.Length == 2 && teclas[0] == 0x12 && teclas[1] == VK_F4)   // ALT+F4
            {
                bool ok = FecharJanelaEmFoco();
                Log("comando Fechar (WM_SYSCOMMAND SC_CLOSE) " + (ok ? "enviado" : "NAO enviado") +
                    " para " + alvo + "." + (ok ? "" : " (atencao: janela elevada ou inexistente)"));
                return ok;
            }

            int enviados = EnviarTeclas(teclas);
            int esperados = teclas.Length * 2;
            Log("SendInput retornou " + enviados.ToString() + "/" + esperados.ToString() + " eventos, para " + alvo + "." +
                (enviados == esperados ? "" : " (atencao: envio bloqueado ou recusado pelo Windows)"));
            return enviados > 0;
        }
        catch (Exception ex)
        {
            Log("falha ao enviar " + nome + ": " + ex.Message);
            return false;
        }
    }

    // Envia um atalho qualquer: aperta as teclas na ordem e solta na ordem inversa.
    internal static int EnviarTeclas(ushort[] teclas)
    {
        INPUT[] aperta = new INPUT[teclas.Length];
        INPUT[] solta = new INPUT[teclas.Length];
        for (int i = 0; i < teclas.Length; i++)
        {
            aperta[i] = MakeKey(teclas[i], false);
            solta[teclas.Length - 1 - i] = MakeKey(teclas[i], true);
        }
        int tamanho = Marshal.SizeOf(typeof(INPUT));

        uint total = SendInput((uint)aperta.Length, aperta, tamanho);
        if (_holdMs > 0) Thread.Sleep(_holdMs);
        total += SendInput((uint)solta.Length, solta, tamanho);

        return (int)total;
    }

    // Teclas que o Windows espera com a flag "estendida" (setas, Insert/Delete,
    // Home/End, PgUp/PgDn, Win, Menu, teclas de midia e volume).
    private static bool TeclaEstendida(ushort vk)
    {
        return (vk >= 0x21 && vk <= 0x28) || vk == 0x2D || vk == 0x2E ||
               (vk >= 0x5B && vk <= 0x5D) || (vk >= 0xA6 && vk <= 0xB7);
    }

    private static INPUT MakeKey(ushort teclaVirtual, bool soltar)
    {
        INPUT entrada = new INPUT();
        entrada.type = INPUT_KEYBOARD;
        entrada.u.ki.wVk = teclaVirtual;
        // Scan code junto com a tecla virtual: apps modernos (Bloco de Notas do
        // Windows 11, WinUI/XAML) ignoram teclas injetadas sem scan code.
        entrada.u.ki.wScan = (ushort)MapVirtualKey(teclaVirtual, MAPVK_VK_TO_VSC);
        entrada.u.ki.dwFlags = (soltar ? KEYEVENTF_KEYUP : 0) | (TeclaEstendida(teclaVirtual) ? KEYEVENTF_EXTENDEDKEY : 0);
        entrada.u.ki.time = 0;
        entrada.u.ki.dwExtraInfo = IntPtr.Zero;
        return entrada;
    }

    // -------------------------------------------------------------------
    // Filtro opcional por aplicativo (desligado por padrao)
    // -------------------------------------------------------------------
    private static bool PrimeiroPlanoCasa(string processoEsperado)
    {
        IntPtr janela = GetForegroundWindow();
        if (janela == IntPtr.Zero) return false;

        uint pid;
        GetWindowThreadProcessId(janela, out pid);
        if (pid == 0) return false;

        // Cache de uma posicao: evita consultar o processo a cada evento.
        if ((int)pid == _ultimoPid) return _ultimoPidCasa;

        bool casou = false;
        try
        {
            using (Process p = Process.GetProcessById((int)pid))
            {
                casou = NormalizeProcess(p.ProcessName) == processoEsperado;
            }
        }
        catch
        {
            casou = false;
        }

        _ultimoPid = (int)pid;
        _ultimoPidCasa = casou;
        return casou;
    }

    // ALT+F4 sem teclado: manda para a janela em primeiro plano o mesmo comando que
    // o ALT+F4 gera por dentro (o "Fechar" do menu da janela). Apps WinUI, como o
    // Bloco de Notas do Windows 11 com o cursor na area de texto, engolem o ALT
    // injetado; o comando de sistema chega igual em qualquer programa (e o programa
    // continua podendo perguntar se quer salvar).
    internal static bool FecharJanelaEmFoco()
    {
        IntPtr janela = GetForegroundWindow();
        if (janela == IntPtr.Zero) return false;
        return PostMessage(janela, WM_SYSCOMMAND, new IntPtr(SC_CLOSE), IntPtr.Zero);
    }

    // Para o log: qual programa vai receber o atalho.
    internal static string DescreverPrimeiroPlano()
    {
        IntPtr janela = GetForegroundWindow();
        if (janela == IntPtr.Zero) return "(nenhuma janela em primeiro plano)";
        uint pid;
        GetWindowThreadProcessId(janela, out pid);
        try
        {
            using (Process p = Process.GetProcessById((int)pid))
            {
                return p.ProcessName + ".exe (PID " + pid.ToString() + ")";
            }
        }
        catch
        {
            return "PID " + pid.ToString();
        }
    }

    private static string NormalizeProcess(string nome)
    {
        string n = nome.Trim().ToLowerInvariant();
        if (n.EndsWith(".exe")) n = n.Substring(0, n.Length - 4);
        return n;
    }

    // -------------------------------------------------------------------
    // Log
    // -------------------------------------------------------------------
    public static void Log(string mensagem)
    {
        lock (_sync)
        {
            if (_log == null) return;
            try
            {
                _log.WriteLine(DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss.fff") + "  " + mensagem);
            }
            catch { }
        }
    }
}

// ---------------------------------------------------------------------------
// Botao pequeno abaixo da roda (Logitech M535 e parecidos), via HID++ 2.0.
//
// Sem software da Logitech, o mouse manda esse botao como um atalho de teclado
// (Win+Tab, a Visao de Tarefas), indistinguivel de um teclado de verdade. O que
// o Logi Options faz -- e o que fazemos aqui -- e' pedir ao proprio mouse, pelo
// canal HID++ (colecao HID do fornecedor, pagina 0xFF00), que DESVIE o controle:
// recurso 0x1B04 (REPROG_CONTROLS_V4), funcao setCidReporting com divert=1.
// A partir dai o mouse deixa de mandar o Win+Tab e passa a mandar uma
// notificacao HID++ com a lista de controles apertados, que lemos aqui.
//
// O desvio fica na memoria do mouse: some se ele desligar ou reiniciar. Por isso
// e' reaplicado quando o mouse volta a mexer depois de parado, e desfeito no
// encerramento limpo (Stop) para o botao voltar ao normal.
// ---------------------------------------------------------------------------
public static class LogiSmallButton
{
    private const ushort RECURSO_REPROG_V4 = 0x1B04;
    private const byte DISPOSITIVO = 0xFF;      // Bluetooth direto (sem receptor Unifying/Bolt)
    private const byte SW_ID = 0x0A;            // identifica as nossas requisicoes nas respostas
    private const byte RELATORIO_LONGO = 0x11;  // HID++ longo: 20 bytes
    private const int TIMEOUT_MS = 1500;

    private static Guid GUID_HID = new Guid("4d1e55b2-f16f-11cf-88cb-001111000030");

    // ---- P/Invoke ----
    [StructLayout(LayoutKind.Sequential)]
    private struct SP_DEVICE_INTERFACE_DATA
    {
        public int cbSize;
        public Guid InterfaceClassGuid;
        public int Flags;
        public IntPtr Reserved;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct HIDP_CAPS
    {
        public ushort Usage;
        public ushort UsagePage;
        public ushort InputReportByteLength;
        public ushort OutputReportByteLength;
        public ushort FeatureReportByteLength;
        [MarshalAs(UnmanagedType.ByValArray, SizeConst = 17)] public ushort[] Reserved;
        public ushort NumberLinkCollectionNodes;
        public ushort NumberInputButtonCaps;
        public ushort NumberInputValueCaps;
        public ushort NumberInputDataIndices;
        public ushort NumberOutputButtonCaps;
        public ushort NumberOutputValueCaps;
        public ushort NumberOutputDataIndices;
        public ushort NumberFeatureButtonCaps;
        public ushort NumberFeatureValueCaps;
        public ushort NumberFeatureDataIndices;
    }

    [DllImport("setupapi.dll", SetLastError = true)]
    private static extern IntPtr SetupDiGetClassDevs(ref Guid classGuid, IntPtr enumerator, IntPtr hwndParent, int flags);

    [DllImport("setupapi.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetupDiEnumDeviceInterfaces(IntPtr infoSet, IntPtr devInfo, ref Guid classGuid, int index, ref SP_DEVICE_INTERFACE_DATA data);

    [DllImport("setupapi.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetupDiGetDeviceInterfaceDetail(IntPtr infoSet, ref SP_DEVICE_INTERFACE_DATA data, IntPtr detail, int detailSize, out int requiredSize, IntPtr devInfo);

    [DllImport("setupapi.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetupDiDestroyDeviceInfoList(IntPtr infoSet);

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern SafeFileHandle CreateFile(string nome, uint acesso, uint compartilhamento, IntPtr seguranca, uint disposicao, uint flags, IntPtr modelo);

    [DllImport("hid.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool HidD_GetPreparsedData(SafeFileHandle h, out IntPtr dados);

    [DllImport("hid.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool HidD_FreePreparsedData(IntPtr dados);

    [DllImport("hid.dll")]
    private static extern int HidP_GetCaps(IntPtr dados, out HIDP_CAPS caps);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool ReadFile(SafeFileHandle h, IntPtr buffer, int tamanho, IntPtr lidos, IntPtr overlapped);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool WriteFile(SafeFileHandle h, IntPtr buffer, int tamanho, IntPtr escritos, IntPtr overlapped);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetOverlappedResult(SafeFileHandle h, IntPtr overlapped, out int transferidos, [MarshalAs(UnmanagedType.Bool)] bool esperar);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CancelIoEx(SafeFileHandle h, IntPtr overlapped);

    private const int ERROR_IO_PENDING = 997;
    // OVERLAPPED: 2 ULONG_PTR + 2 DWORD + HANDLE (hEvent por ultimo).
    private static readonly int TAM_OVERLAPPED = IntPtr.Size == 8 ? 32 : 20;

    // ---- Configuracao ----
    private static ushort _cid = 0x00D0;
    private static volatile ushort[] _teclas;
    private static volatile string _nomeAtalho = "";
    private static bool _dryRun;
    private static int _ociosoMs = 15000;

    // ---- Estado ----
    private static Thread _thread;
    private static volatile bool _running;
    private static ManualResetEvent _parar = new ManualResetEvent(false);
    private static volatile bool _reaplicar;
    private static AutoResetEvent _acordar = new AutoResetEvent(false);
    private static string _ultimoAviso;
    private static volatile bool _desviado;
    private static int _ultimaAtividade;
    private static volatile string _estado = "desligado";
    private static long _apertos;

    // Sessao com o dispositivo: so' a thread do botao mexe nisto.
    private static SafeFileHandle _handle;
    private static OperacaoHid _leitura;
    private static OperacaoHid _escrita;
    private static int _tamSaida;
    private static byte _indiceRecurso;
    private static bool _apertado;

    public static string Estado
    {
        get { return _estado; }
    }

    public static long Presses
    {
        get { return Interlocked.Read(ref _apertos); }
    }

    // -------------------------------------------------------------------
    // API publica
    // -------------------------------------------------------------------
    public static void Start(int cid, ushort[] teclas, string nomeAtalho, bool dryRun)
    {
        if (_running) return;

        _cid = (ushort)cid;
        _teclas = teclas;
        _nomeAtalho = nomeAtalho;
        _dryRun = dryRun;
        _parar = new ManualResetEvent(false);
        _reaplicar = false;
        _desviado = false;
        _ultimoAviso = null;
        _apertos = 0;
        _estado = "procurando o mouse...";

        _running = true;
        _thread = new Thread(ThreadMain);
        _thread.IsBackground = true;
        _thread.Name = "LogiSmallButton";
        _thread.Start();
    }

    // Troca o atalho sem mexer no desvio do mouse.
    public static void SetKeys(ushort[] teclas, string nomeAtalho)
    {
        _teclas = teclas;
        _nomeAtalho = nomeAtalho;
        if (_desviado) _estado = "ativo -> " + nomeAtalho;
    }

    public static bool Running
    {
        get { return _running; }
    }

    public static void Stop()
    {
        if (!_running) return;
        _running = false;
        _parar.Set();
        if (_thread != null)
        {
            // A thread desfaz o desvio antes de sair (ate' TIMEOUT_MS por escrita).
            try { _thread.Join(5000); } catch { }
            _thread = null;
        }
        _estado = "desligado";
    }

    // Chamado pelo hook de mouse a cada evento: tem que ser baratissimo.
    internal static void NotarAtividade()
    {
        if (!_running) return;
        int agora = Environment.TickCount;
        int anterior = _ultimaAtividade;
        _ultimaAtividade = agora;
        if (anterior != 0 && unchecked(agora - anterior) > _ociosoMs)
        {
            if (_desviado) _reaplicar = true;   // pode ter acordado sem o desvio
            else _acordar.Set();                // estava sem mouse: procura de novo ja'
        }
    }

    // -------------------------------------------------------------------
    // Thread do botao
    // -------------------------------------------------------------------
    private static void ThreadMain()
    {
        while (_running)
        {
            string caminho = null;
            try
            {
                caminho = AbrirMouse();
                if (caminho == null)
                {
                    Avisar("nenhum mouse Logitech com o controle 0x" + _cid.ToString("X4") +
                        " respondendo (procurando de novo a cada 5 s ou quando o mouse mexer).");
                    _estado = "mouse nao encontrado (procurando)";
                    Esperar(5000);
                    continue;
                }

                _ultimoAviso = null;
                if (!Desviar(true))
                {
                    throw new IOException("o mouse recusou o desvio: " + _ultimoErro);
                }
                _desviado = true;
                _apertado = false;
                _estado = "ativo -> " + _nomeAtalho;
                MiddleClickRemap.Log("botao pequeno: controle 0x" + _cid.ToString("X4") + " desviado em " + caminho + ".");

                while (_running)
                {
                    if (_reaplicar)
                    {
                        _reaplicar = false;
                        if (!Desviar(true)) throw new IOException("falha ao reaplicar o desvio: " + _ultimoErro);
                        MiddleClickRemap.Log("botao pequeno: desvio reaplicado (mouse voltou a mexer depois de parado).");
                    }

                    byte[] relatorio = LerUm(500);
                    if (relatorio != null) TratarRelatorio(relatorio);
                }

                // Encerramento limpo: o botao volta a fazer o que fazia antes.
                if (Desviar(false))
                    MiddleClickRemap.Log("botao pequeno: desvio desfeito (botao volta ao normal).");
                else
                    MiddleClickRemap.Log("botao pequeno: nao consegui desfazer o desvio (" + _ultimoErro +
                        "); desligar e ligar o mouse resolve.");
            }
            catch (Exception ex)
            {
                Exception raiz = ex is AggregateException && ex.InnerException != null ? ex.InnerException : ex;
                MiddleClickRemap.Log("botao pequeno: conexao com o mouse perdida (" + raiz.Message + "); tentando de novo.");
                _estado = "reconectando";
            }
            finally
            {
                _desviado = false;
                Fechar();
            }

            if (_running) Esperar(3000);
        }
    }

    // Espera o tempo dado, a parada, ou o mouse voltar a mexer depois de parado.
    private static void Esperar(int ms)
    {
        WaitHandle.WaitAny(new WaitHandle[] { _parar, _acordar }, ms);
    }

    // Registra so' quando a mensagem muda, para a procura a cada 5 s nao encher o log.
    private static void Avisar(string mensagem)
    {
        if (mensagem == _ultimoAviso) return;
        _ultimoAviso = mensagem;
        MiddleClickRemap.Log("botao pequeno: " + mensagem);
    }

    private static void TratarRelatorio(byte[] r)
    {
        // Notificacao de controles desviados: [0x11, disp, indice 0x1B04, funcao 0 / swId 0, CIDs...]
        if (r.Length < 12 || r[0] != RELATORIO_LONGO || r[2] != _indiceRecurso || r[3] != 0x00) return;

        bool apertado = false;
        for (int i = 4; i + 1 < 12; i += 2)
        {
            ushort cid = (ushort)((r[i] << 8) | r[i + 1]);
            if (cid == _cid) apertado = true;
        }

        if (apertado && !_apertado)
        {
            Interlocked.Increment(ref _apertos);
            if (_dryRun)
            {
                MiddleClickRemap.Log("botao pequeno apertado -> DRY-RUN: enviaria " + _nomeAtalho + " (nao enviado).");
            }
            else
            {
                MiddleClickRemap.Log("botao pequeno apertado -> enviando " + _nomeAtalho + ".");
                ThreadPool.QueueUserWorkItem(EnviarWorker, new object[] { _teclas, _nomeAtalho });
            }
        }
        _apertado = apertado;
    }

    private static void EnviarWorker(object estado)
    {
        object[] dados = (object[])estado;
        MiddleClickRemap.EnviarAtalho((ushort[])dados[0], (string)dados[1]);
    }

    // -------------------------------------------------------------------
    // Descoberta: colecoes HID++ longas (0xFF00/0x0002) de aparelhos Logitech
    // que tenham o recurso 0x1B04 com o controle procurado.
    // -------------------------------------------------------------------
    private static string AbrirMouse()
    {
        foreach (string caminho in ListarInterfacesHid())
        {
            string minusculo = caminho.ToLowerInvariant();
            if (minusculo.IndexOf("vid&0002046d") < 0 && minusculo.IndexOf("vid_046d") < 0) continue;
            if (!EhColecaoHidppLonga(caminho)) continue;

            try
            {
                Abrir(caminho);
                byte[] r = Requisitar(0, 0, new byte[] { (byte)(RECURSO_REPROG_V4 >> 8), (byte)(RECURSO_REPROG_V4 & 0xFF) });
                if (r != null && r[0] != 0)
                {
                    _indiceRecurso = r[0];
                    if (TemControle()) return caminho;
                }
            }
            catch (Exception ex)
            {
                Avisar("sem resposta de " + caminho + " (" + ex.Message + ").");
            }
            Fechar();
        }
        return null;
    }

    private static bool TemControle()
    {
        byte[] r = Requisitar(_indiceRecurso, 0, null);   // getCount
        if (r == null) return false;
        int total = r[0];
        for (int i = 0; i < total; i++)
        {
            byte[] info = Requisitar(_indiceRecurso, 1, new byte[] { (byte)i });   // getCidInfo
            if (info != null && ((info[0] << 8) | info[1]) == _cid) return true;
        }
        return false;
    }

    private static string _ultimoErro;

    // setCidReporting: bit0 = desviar, bit1 = "o bit0 vale" (dvalid).
    private static bool Desviar(bool ligar)
    {
        byte flags = (byte)(ligar ? 0x03 : 0x02);
        return Requisitar(_indiceRecurso, 3, new byte[] { (byte)(_cid >> 8), (byte)(_cid & 0xFF), flags, 0, 0 }) != null;
    }

    private static List<string> ListarInterfacesHid()
    {
        List<string> caminhos = new List<string>();
        IntPtr conjunto = SetupDiGetClassDevs(ref GUID_HID, IntPtr.Zero, IntPtr.Zero, 0x12);   // PRESENT | DEVICEINTERFACE
        if (conjunto == new IntPtr(-1)) return caminhos;
        try
        {
            for (int i = 0; ; i++)
            {
                SP_DEVICE_INTERFACE_DATA dados = new SP_DEVICE_INTERFACE_DATA();
                dados.cbSize = Marshal.SizeOf(typeof(SP_DEVICE_INTERFACE_DATA));
                if (!SetupDiEnumDeviceInterfaces(conjunto, IntPtr.Zero, ref GUID_HID, i, ref dados)) break;

                int necessario;
                SetupDiGetDeviceInterfaceDetail(conjunto, ref dados, IntPtr.Zero, 0, out necessario, IntPtr.Zero);
                if (necessario <= 0) continue;

                IntPtr detalhe = Marshal.AllocHGlobal(necessario);
                try
                {
                    // cbSize de SP_DEVICE_INTERFACE_DETAIL_DATA_W: 8 em 64 bits, 6 em 32 bits.
                    Marshal.WriteInt32(detalhe, IntPtr.Size == 8 ? 8 : 6);
                    if (SetupDiGetDeviceInterfaceDetail(conjunto, ref dados, detalhe, necessario, out necessario, IntPtr.Zero))
                    {
                        caminhos.Add(Marshal.PtrToStringUni(new IntPtr(detalhe.ToInt64() + 4)));
                    }
                }
                finally
                {
                    Marshal.FreeHGlobal(detalhe);
                }
            }
        }
        finally
        {
            SetupDiDestroyDeviceInfoList(conjunto);
        }
        return caminhos;
    }

    private static bool EhColecaoHidppLonga(string caminho)
    {
        // Acesso 0: so' consulta, funciona ate' em colecoes abertas com exclusividade.
        using (SafeFileHandle h = CreateFile(caminho, 0, 3, IntPtr.Zero, 3, 0, IntPtr.Zero))
        {
            if (h.IsInvalid) return false;
            IntPtr dados;
            if (!HidD_GetPreparsedData(h, out dados)) return false;
            HIDP_CAPS caps;
            HidP_GetCaps(dados, out caps);
            HidD_FreePreparsedData(dados);
            return caps.UsagePage == 0xFF00 && caps.Usage == 0x0002 && caps.OutputReportByteLength == 20;
        }
    }

    // -------------------------------------------------------------------
    // E/S HID++. Tudo com timeout e cancelamento explicito: escrita para um
    // mouse Bluetooth dormindo pode ficar pendurada, e isso nao pode travar a
    // thread. Por isso E/S sobreposta direto da API, sem FileStream: o do .NET
    // Framework serializa as operacoes de um mesmo handle (a escrita esperaria a
    // leitura que fica pendente aguardando o proximo aperto) e, fechado com uma
    // escrita pendurada, pode esperar para sempre.
    // -------------------------------------------------------------------
    private sealed class OperacaoHid : IDisposable
    {
        private readonly SafeFileHandle _h;
        private readonly ManualResetEvent _evento = new ManualResetEvent(false);
        private readonly IntPtr _ov;          // OVERLAPPED e buffer em memoria nao gerenciada:
        public readonly IntPtr Buffer;        // o GC nao pode move-los enquanto o driver os usa.
        public readonly int Tamanho;
        public bool Pendente;

        public OperacaoHid(SafeFileHandle h, int tamanho)
        {
            _h = h;
            Tamanho = tamanho;
            Buffer = Marshal.AllocHGlobal(tamanho);
            _ov = Marshal.AllocHGlobal(TAM_OVERLAPPED);
        }

        private void Preparar()
        {
            for (int i = 0; i < TAM_OVERLAPPED; i++) Marshal.WriteByte(_ov, i, 0);
            Marshal.WriteIntPtr(_ov, TAM_OVERLAPPED - IntPtr.Size, _evento.SafeWaitHandle.DangerousGetHandle());
            _evento.Reset();
        }

        public void IniciarLeitura()
        {
            Preparar();
            if (!ReadFile(_h, Buffer, Tamanho, IntPtr.Zero, _ov)) ConferirPendente();
            Pendente = true;
        }

        public void IniciarEscrita(byte[] dados)
        {
            int n = Math.Min(dados.Length, Tamanho);
            Marshal.Copy(dados, 0, Buffer, n);
            Preparar();
            if (!WriteFile(_h, Buffer, n, IntPtr.Zero, _ov)) ConferirPendente();
            Pendente = true;
        }

        private static void ConferirPendente()
        {
            int erro = Marshal.GetLastWin32Error();
            if (erro != ERROR_IO_PENDING) throw new IOException("E/S HID falhou (Win32 erro " + erro.ToString() + ").");
        }

        // Bytes transferidos, ou -1 se ainda estiver pendente.
        public int Esperar(int timeoutMs)
        {
            if (!_evento.WaitOne(timeoutMs)) return -1;
            int n;
            bool ok = GetOverlappedResult(_h, _ov, out n, false);
            Pendente = false;
            if (!ok) throw new IOException("E/S HID falhou (Win32 erro " + Marshal.GetLastWin32Error().ToString() + ").");
            return n;
        }

        public void Cancelar()
        {
            if (!Pendente) return;
            CancelIoEx(_h, _ov);
            if (_evento.WaitOne(2000))
            {
                int n;
                GetOverlappedResult(_h, _ov, out n, false);
                Pendente = false;
            }
        }

        public void Dispose()
        {
            Cancelar();
            if (Pendente) return;   // o driver ainda segura a memoria: melhor vazar do que corromper
            Marshal.FreeHGlobal(Buffer);
            Marshal.FreeHGlobal(_ov);
            _evento.Dispose();
        }
    }

    private static void Abrir(string caminho)
    {
        // GENERIC_READ|GENERIC_WRITE, compartilhado, OPEN_EXISTING, FILE_FLAG_OVERLAPPED
        _handle = CreateFile(caminho, 0xC0000000, 3, IntPtr.Zero, 3, 0x40000000, IntPtr.Zero);
        if (_handle.IsInvalid)
        {
            int erro = Marshal.GetLastWin32Error();
            _handle.Dispose();
            _handle = null;
            throw new IOException("CreateFile falhou (Win32 erro " + erro.ToString() + ").");
        }

        IntPtr dados;
        HIDP_CAPS caps = new HIDP_CAPS();
        if (HidD_GetPreparsedData(_handle, out dados))
        {
            HidP_GetCaps(dados, out caps);
            HidD_FreePreparsedData(dados);
        }
        _tamSaida = caps.OutputReportByteLength;
        _leitura = new OperacaoHid(_handle, Math.Max((int)caps.InputReportByteLength, 20));
        _escrita = new OperacaoHid(_handle, Math.Max(_tamSaida, 20));
    }

    private static void Fechar()
    {
        if (_leitura != null) { try { _leitura.Dispose(); } catch { } _leitura = null; }
        if (_escrita != null) { try { _escrita.Dispose(); } catch { } _escrita = null; }
        if (_handle != null) { try { _handle.Dispose(); } catch { } _handle = null; }
    }

    // Le um relatorio; null se nada chegar no prazo (a leitura continua pendente
    // e e' aproveitada na proxima chamada).
    private static byte[] LerUm(int timeoutMs)
    {
        if (!_leitura.Pendente) _leitura.IniciarLeitura();
        int lidos = _leitura.Esperar(timeoutMs);
        if (lidos < 0) return null;
        if (lidos == 0) throw new IOException("leitura vazia (dispositivo removido?)");
        byte[] r = new byte[lidos];
        Marshal.Copy(_leitura.Buffer, r, 0, lidos);
        return r;
    }

    // Requisicao HID++ 2.0; devolve os parametros da resposta (a partir do byte 4)
    // ou null (erro/timeout, com o motivo em _ultimoErro). Notificacoes que chegam
    // no meio do caminho sao tratadas normalmente.
    private static byte[] Requisitar(byte recurso, byte funcao, byte[] parametros)
    {
        byte[] saida = new byte[_tamSaida];
        saida[0] = RELATORIO_LONGO;
        saida[1] = DISPOSITIVO;
        saida[2] = recurso;
        saida[3] = (byte)((funcao << 4) | SW_ID);
        if (parametros != null) Array.Copy(parametros, 0, saida, 4, Math.Min(parametros.Length, _tamSaida - 4));

        _escrita.Cancelar();
        _escrita.IniciarEscrita(saida);
        if (_escrita.Esperar(TIMEOUT_MS) < 0)
        {
            _escrita.Cancelar();
            throw new IOException("escrita HID++ sem resposta (mouse dormindo?)");
        }

        DateTime limite = DateTime.UtcNow.AddMilliseconds(TIMEOUT_MS);
        while (true)
        {
            int resta = (int)(limite - DateTime.UtcNow).TotalMilliseconds;
            if (resta <= 0) break;
            byte[] r = LerUm(resta);
            if (r == null) break;
            if (r.Length < 6 || r[1] != DISPOSITIVO)
            {
                continue;
            }
            if (r[2] == recurso && r[3] == saida[3])
            {
                byte[] resposta = new byte[r.Length - 4];
                Array.Copy(r, 4, resposta, 0, resposta.Length);
                return resposta;
            }
            if (r[2] == 0xFF && r[3] == recurso && r[4] == saida[3])
            {
                _ultimoErro = "erro HID++ 0x" + r[5].ToString("X2");
                return null;
            }
            if (r[2] == 0x8F && r[3] == recurso)
            {
                _ultimoErro = "erro HID++ 1.0 0x" + r[5].ToString("X2");
                return null;
            }
            TratarRelatorio(r);
        }
        _ultimoErro = "sem resposta";
        return null;
    }
}

// Ctrl+C no console vira um pedido de parada limpa (o mesmo evento do
// Parar-Remap.cmd), em vez de matar o processo no meio do loop do WinForms.
public static class SinalCtrlC
{
    private static EventWaitHandle _evento;
    private static ConsoleCancelEventHandler _tratador;

    public static void Instalar(EventWaitHandle evento)
    {
        _evento = evento;
        _tratador = delegate(object remetente, ConsoleCancelEventArgs e)
        {
            e.Cancel = true;
            _evento.Set();
        };
        try { Console.CancelKeyPress += _tratador; } catch { }
    }
}
'@

if (-not ('MiddleClickRemap' -as [type])) {
    Add-Type -TypeDefinition $codigoCSharp -Language CSharp -ErrorAction Stop
}

# ---------------------------------------------------------------------------
# Atalhos: 'CTRL+SHIFT+T' -> codigos de tecla virtual.
# ---------------------------------------------------------------------------
function ConvertTo-TeclasVirtuais {
    param([string]$Atalho)

    $nomes = @{
        'CTRL' = 0x11; 'CONTROL' = 0x11; 'ALT' = 0x12; 'SHIFT' = 0x10; 'WIN' = 0x5B
        'ENTER' = 0x0D; 'ESC' = 0x1B; 'ESCAPE' = 0x1B; 'TAB' = 0x09; 'SPACE' = 0x20; 'BACKSPACE' = 0x08
        'DELETE' = 0x2E; 'DEL' = 0x2E; 'INSERT' = 0x2D; 'HOME' = 0x24; 'END' = 0x23
        'PGUP' = 0x21; 'PAGEUP' = 0x21; 'PGDN' = 0x22; 'PAGEDOWN' = 0x22
        'LEFT' = 0x25; 'UP' = 0x26; 'RIGHT' = 0x27; 'DOWN' = 0x28
        'PLAYPAUSE' = 0xB3; 'NEXTTRACK' = 0xB0; 'PREVTRACK' = 0xB1; 'STOP' = 0xB2
        'MUTE' = 0xAD; 'VOLDOWN' = 0xAE; 'VOLUP' = 0xAF
    }

    $teclas = New-Object System.Collections.Generic.List[uint16]
    foreach ($parte in ([string]$Atalho -split '\+')) {
        $nome = $parte.Trim().ToUpperInvariant()
        if ($nome -eq '') { throw "Atalho invalido: '$Atalho'." }
        if ($nomes.ContainsKey($nome)) { $teclas.Add([uint16]$nomes[$nome]) }
        elseif ($nome -match '^[A-Z0-9]$') { $teclas.Add([uint16][char]$nome) }
        elseif ($nome -match '^F([1-9]|1[0-9]|2[0-4])$') { $teclas.Add([uint16](0x6F + [int]$Matches[1])) }
        else { throw "Tecla desconhecida no atalho '$Atalho': '$($parte.Trim())'." }
    }
    return , $teclas.ToArray()
}

# ---------------------------------------------------------------------------
# Configuracao: padroes < arquivo config.json (janela de configuracoes) <
# parametros passados na linha de comando. O arquivo fica no perfil do usuario,
# fora da pasta do programa, para sobreviver a atualizacoes.
# ---------------------------------------------------------------------------
$arquivoConfig = Join-Path (Join-Path $env:APPDATA 'MiddleClick-CtrlF4') 'config.json'
$atalhoInicializar = Join-Path ([Environment]::GetFolderPath('Startup')) 'Remap botao do meio.lnk'

function New-ConfigPadrao {
    [pscustomobject]@{
        MiddleClick = [pscustomobject]@{ Enabled = $true; Keys = 'CTRL+F4'; OnlyProcess = '' }
        ScrollAccel = [pscustomobject]@{ Enabled = $true; MaxFactor = 5; FastMs = 80; RampNotches = 2 }
        SmallButton = [pscustomobject]@{ Enabled = $true; Keys = 'ALT+F4' }
    }
}

# Copia por cima do padrao so' os campos conhecidos e do tipo certo: um arquivo
# editado a mao ou de versao antiga nunca impede o remapeamento de subir.
function Read-ConfigArquivo {
    param($Config)
    if (-not (Test-Path -LiteralPath $arquivoConfig)) { return $Config }
    try {
        $lido = Get-Content -LiteralPath $arquivoConfig -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        Write-Warning ("Ignorando " + $arquivoConfig + " (JSON invalido): " + $_.Exception.Message)
        return $Config
    }
    foreach ($secao in $Config.PSObject.Properties) {
        $origem = $lido.PSObject.Properties[$secao.Name]
        if (-not $origem -or $null -eq $origem.Value) { continue }
        foreach ($campo in $secao.Value.PSObject.Properties) {
            $valor = $origem.Value.PSObject.Properties[$campo.Name]
            if (-not $valor -or $null -eq $valor.Value) { continue }
            $convertido = $valor.Value -as $campo.Value.GetType()
            if ($null -ne $convertido) { $campo.Value = $convertido }
        }
    }
    foreach ($secao in 'MiddleClick', 'SmallButton') {
        try { [void](ConvertTo-TeclasVirtuais $Config.$secao.Keys) }
        catch {
            Write-Warning ("Atalho invalido em " + $arquivoConfig + " (" + $secao + "): " + $_.Exception.Message + " Usando o padrao.")
            $Config.$secao.Keys = (New-ConfigPadrao).$secao.Keys
        }
    }
    return $Config
}

function Save-ConfigArquivo {
    param($Config)
    $pasta = Split-Path -Parent $arquivoConfig
    if (-not (Test-Path -LiteralPath $pasta)) { [void](New-Item -ItemType Directory -Path $pasta) }
    $Config | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $arquivoConfig -Encoding UTF8
}

function Copy-Config {
    param($Config)
    return ($Config | ConvertTo-Json -Depth 4 | ConvertFrom-Json)
}

$config = New-ConfigPadrao
if (-not $IgnoreConfig.IsPresent) { $config = Read-ConfigArquivo $config }

# Parametros explicitos ganham do arquivo (e um atalho invalido aqui e' erro).
$p = $PSBoundParameters
if ($p.ContainsKey('NoMiddleClick')) { $config.MiddleClick.Enabled = -not $NoMiddleClick.IsPresent }
if ($p.ContainsKey('MiddleClickKeys')) { [void](ConvertTo-TeclasVirtuais $MiddleClickKeys); $config.MiddleClick.Keys = $MiddleClickKeys }
if ($p.ContainsKey('OnlyProcess')) { $config.MiddleClick.OnlyProcess = $OnlyProcess }
if ($p.ContainsKey('NoScrollAccel')) { $config.ScrollAccel.Enabled = -not $NoScrollAccel.IsPresent }
if ($p.ContainsKey('ScrollMaxFactor')) { $config.ScrollAccel.MaxFactor = $ScrollMaxFactor }
if ($p.ContainsKey('ScrollFastMs')) { $config.ScrollAccel.FastMs = $ScrollFastMs }
if ($p.ContainsKey('ScrollRampNotches')) { $config.ScrollAccel.RampNotches = $ScrollRampNotches }
if ($p.ContainsKey('NoSmallButton')) { $config.SmallButton.Enabled = -not $NoSmallButton.IsPresent }
if ($p.ContainsKey('SmallButtonKeys')) { [void](ConvertTo-TeclasVirtuais $SmallButtonKeys); $config.SmallButton.Keys = $SmallButtonKeys }
foreach ($secao in 'MiddleClick', 'SmallButton') { $config.$secao.Keys = $config.$secao.Keys.ToUpperInvariant() }

# Liga/desliga e reconfigura as tres funcoes. Pode ser chamado com tudo rodando
# (janela de configuracoes, pausa); -Pausar desliga as tres sem mexer na config.
function Set-Funcoes {
    param($Config, [switch]$Pausar)

    $meio = $Config.MiddleClick
    [MiddleClickRemap]::ConfigureMiddleClick(($meio.Enabled -and -not $Pausar),
        (ConvertTo-TeclasVirtuais $meio.Keys), $meio.Keys, $meio.OnlyProcess)

    $rolagem = $Config.ScrollAccel
    [MiddleClickRemap]::ConfigureScrollAccel(($rolagem.Enabled -and -not $Pausar),
        $rolagem.FastMs, $rolagem.RampNotches, $rolagem.MaxFactor, $ScrollAccelInjected.IsPresent)

    $botao = $Config.SmallButton
    if ($botao.Enabled -and -not $Pausar) {
        $teclas = ConvertTo-TeclasVirtuais $botao.Keys
        if ([LogiSmallButton]::Running) { [LogiSmallButton]::SetKeys($teclas, $botao.Keys) }
        else { [LogiSmallButton]::Start($SmallButtonCid, $teclas, $botao.Keys, $DryRun.IsPresent) }
    }
    elseif ([LogiSmallButton]::Running) {
        [LogiSmallButton]::Stop()   # devolve o botao ao normal (Visao de Tarefas)
    }
}

# Pedido de parada limpa vindo de fora (Parar-Remap.cmd / Instalar.cmd / Sair na
# bandeja / Ctrl+C): sem ele so' daria para matar o processo, e o botao pequeno
# ficaria desviado e mudo ate' o mouse ser desligado e ligado.
$eventoParar = New-Object System.Threading.EventWaitHandle($false, [System.Threading.EventResetMode]::ManualReset, 'Local\MiddleClick-CtrlF4-Parar')
[void]$eventoParar.Reset()
# Uma segunda copia do script (ex.: duplo clique de novo no Iniciar-Remap.vbs)
# sinaliza este evento para abrir a janela de configuracoes desta.
$eventoConfigurar = New-Object System.Threading.EventWaitHandle($false, [System.Threading.EventResetMode]::AutoReset, 'Local\MiddleClick-CtrlF4-Configurar')
[SinalCtrlC]::Instalar($eventoParar)

$usarBandeja = (-not $NoTray.IsPresent) -and
    ([System.Threading.Thread]::CurrentThread.GetApartmentState() -eq [System.Threading.ApartmentState]::STA)

# ---------------------------------------------------------------------------
# Icone na bandeja e janela de configuracoes (WinForms)
# ---------------------------------------------------------------------------
function New-IconeMouse {
    param([bool]$Ativo)
    $bmp = New-Object System.Drawing.Bitmap 32, 32
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $cor = if ($Ativo) { [System.Drawing.Color]::FromArgb(0, 120, 212) } else { [System.Drawing.Color]::FromArgb(140, 140, 140) }

    $x = 7; $y = 1; $w = 18; $h = 30; $d = 16
    $corpo = New-Object System.Drawing.Drawing2D.GraphicsPath
    $corpo.AddArc($x, $y, $d, $d, 180, 90)
    $corpo.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
    $corpo.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
    $corpo.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
    $corpo.CloseFigure()
    $pincel = New-Object System.Drawing.SolidBrush $cor
    $g.FillPath($pincel, $corpo)

    $branco = New-Object System.Drawing.Pen ([System.Drawing.Color]::White), 2
    $g.DrawLine($branco, 16, 2, 16, 13)          # divisao entre os botoes
    $g.DrawLine($branco, 8, 13, 24, 13)          # fim dos botoes
    $g.FillRectangle([System.Drawing.Brushes]::White, 14, 5, 4, 6)   # roda

    $g.Dispose(); $pincel.Dispose(); $branco.Dispose(); $corpo.Dispose()
    return [System.Drawing.Icon]::FromHandle($bmp.GetHicon())
}

$script:pausado = $false
$script:janela = $null

function Update-Bandeja {
    if (-not $script:bandeja) { return }
    if ($script:pausado) {
        $script:bandeja.Icon = $script:iconePausado
        $script:bandeja.Text = 'Remap do mouse: pausado'
        $script:itemPausar.Text = 'Retomar'
    }
    else {
        $script:bandeja.Icon = $script:iconeAtivo
        $texto = 'Remap do mouse: ativo'
        if ($DryRun.IsPresent) { $texto += ' (DRY-RUN)' }
        $script:bandeja.Text = $texto
        $script:itemPausar.Text = 'Pausar'
    }
}

function Switch-Pausa {
    $script:pausado = -not $script:pausado
    Set-Funcoes -Config $script:config -Pausar:$script:pausado
    [MiddleClickRemap]::Log($(if ($script:pausado) { 'pausado pela bandeja.' } else { 'retomado pela bandeja.' }))
    Update-Bandeja
}

function Set-IniciarComWindows {
    param([bool]$Ligar)
    if ($Ligar) {
        $ws = New-Object -ComObject WScript.Shell
        $lnk = $ws.CreateShortcut($atalhoInicializar)
        $lnk.TargetPath = Join-Path $env:SystemRoot 'System32\wscript.exe'
        $lnk.Arguments = '"' + (Join-Path $PSScriptRoot 'Iniciar-Remap.vbs') + '"'
        $lnk.WorkingDirectory = $PSScriptRoot
        $lnk.Description = 'Remap do mouse: botao do meio, rolagem e botao pequeno'
        $lnk.Save()
    }
    elseif (Test-Path -LiteralPath $atalhoInicializar) {
        Remove-Item -LiteralPath $atalhoInicializar -Force
    }
}

function Show-Configuracoes {
    if ($script:janela) { $script:janela.Activate(); return }

    $presets = @('CTRL+F4', 'CTRL+W', 'ALT+F4', 'CTRL+T', 'CTRL+SHIFT+T', 'CTRL+TAB', 'WIN+D', 'ENTER', 'ESC', 'PLAYPAUSE', 'MUTE')
    $c = $script:config

    $f = New-Object System.Windows.Forms.Form
    $f.Text = 'Remap do mouse — Configurações'
    $f.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $f.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Font
    $f.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $f.MaximizeBox = $false
    $f.MinimizeBox = $false
    $f.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
    $f.ClientSize = New-Object System.Drawing.Size 470, 470
    $f.Icon = $script:iconeAtivo
    $f.ShowInTaskbar = $true

    function Add-Controle($pai, $controle, $x, $y, $w, $h) {
        $controle.Location = New-Object System.Drawing.Point $x, $y
        if ($w) { $controle.Width = $w }
        if ($h) { $controle.Height = $h }
        $pai.Controls.Add($controle)
        return $controle
    }
    function New-Rotulo($texto) {
        $r = New-Object System.Windows.Forms.Label
        $r.Text = $texto
        $r.AutoSize = $true
        return $r
    }
    function New-Atalho($valor) {
        $cb = New-Object System.Windows.Forms.ComboBox
        $cb.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDown
        $cb.Items.AddRange([object[]]$presets)
        $cb.Text = $valor
        return $cb
    }

    # --- Botao do meio ---
    $g1 = Add-Controle $f (New-Object System.Windows.Forms.GroupBox) 12 10 446 118
    $g1.Text = 'Botão do meio (clique na roda)'
    $chkMeio = Add-Controle $g1 (New-Object System.Windows.Forms.CheckBox) 14 24 300 0
    $chkMeio.Text = 'Ativar'; $chkMeio.Checked = [bool]$c.MiddleClick.Enabled
    [void](Add-Controle $g1 (New-Rotulo 'Atalho:') 30 55 0 0)
    $cbMeio = Add-Controle $g1 (New-Atalho $c.MiddleClick.Keys) 200 51 220 0
    [void](Add-Controle $g1 (New-Rotulo 'Só no programa (vazio = todos):') 30 86 0 0)
    $txtPrograma = Add-Controle $g1 (New-Object System.Windows.Forms.TextBox) 200 82 220 0
    $txtPrograma.Text = $c.MiddleClick.OnlyProcess

    # --- Rolagem ---
    $g2 = Add-Controle $f (New-Object System.Windows.Forms.GroupBox) 12 138 446 150
    $g2.Text = 'Aceleração da rolagem'
    $chkRol = Add-Controle $g2 (New-Object System.Windows.Forms.CheckBox) 14 24 300 0
    $chkRol.Text = 'Ativar'; $chkRol.Checked = [bool]$c.ScrollAccel.Enabled
    [void](Add-Controle $g2 (New-Rotulo 'Aceleração máxima:') 30 55 0 0)
    $numFator = Add-Controle $g2 (New-Object System.Windows.Forms.NumericUpDown) 200 52 60 0
    $numFator.Minimum = 2; $numFator.Maximum = 20
    $numFator.Value = [Math]::Min(20, [Math]::Max(2, [int]$c.ScrollAccel.MaxFactor))
    [void](Add-Controle $g2 (New-Rotulo 'vezes') 266 55 0 0)
    [void](Add-Controle $g2 (New-Rotulo 'Acelera a partir de giros:') 30 90 0 0)
    $trkVel = Add-Controle $g2 (New-Object System.Windows.Forms.TrackBar) 196 84 180 0
    $trkVel.Minimum = 40; $trkVel.Maximum = 200; $trkVel.SmallChange = 10; $trkVel.LargeChange = 20; $trkVel.TickFrequency = 20
    $trkVel.Value = [Math]::Min(200, [Math]::Max(40, [int]$c.ScrollAccel.FastMs))
    $lblVel = Add-Controle $g2 (New-Rotulo '') 380 90 0 0
    [void](Add-Controle $g2 (New-Rotulo 'rápidos') 196 122 0 0)
    [void](Add-Controle $g2 (New-Rotulo 'mais lentos') 318 122 0 0)
    $atualizarVel = { $lblVel.Text = [string]$trkVel.Value + ' ms' }
    & $atualizarVel
    $trkVel.add_ValueChanged($atualizarVel)

    # --- Botao pequeno ---
    $g3 = Add-Controle $f (New-Object System.Windows.Forms.GroupBox) 12 298 446 112
    $g3.Text = 'Botão pequeno abaixo da roda (Logitech M535)'
    $chkBotao = Add-Controle $g3 (New-Object System.Windows.Forms.CheckBox) 14 24 420 0
    $chkBotao.Text = 'Ativar (desligado, volta a abrir a Visão de Tarefas)'; $chkBotao.Checked = [bool]$c.SmallButton.Enabled
    [void](Add-Controle $g3 (New-Rotulo 'Atalho:') 30 55 0 0)
    $cbBotao = Add-Controle $g3 (New-Atalho $c.SmallButton.Keys) 200 51 220 0
    [void](Add-Controle $g3 (New-Rotulo 'Mouse:') 30 86 0 0)
    $lblEstado = Add-Controle $g3 (New-Rotulo '') 200 86 0 0

    # --- Rodape ---
    $chkWindows = Add-Controle $f (New-Object System.Windows.Forms.CheckBox) 14 426 220 0
    $chkWindows.Text = 'Iniciar com o Windows'
    $chkWindows.Checked = Test-Path -LiteralPath $atalhoInicializar
    $btnSalvar = Add-Controle $f (New-Object System.Windows.Forms.Button) 284 422 84 28
    $btnSalvar.Text = 'Salvar'
    $btnCancelar = Add-Controle $f (New-Object System.Windows.Forms.Button) 374 422 84 28
    $btnCancelar.Text = 'Cancelar'
    $btnCancelar.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $f.AcceptButton = $btnSalvar
    $f.CancelButton = $btnCancelar

    $habilitar = {
        $cbMeio.Enabled = $chkMeio.Checked; $txtPrograma.Enabled = $chkMeio.Checked
        $numFator.Enabled = $chkRol.Checked; $trkVel.Enabled = $chkRol.Checked
        $cbBotao.Enabled = $chkBotao.Checked
    }
    & $habilitar
    $chkMeio.add_CheckedChanged($habilitar)
    $chkRol.add_CheckedChanged($habilitar)
    $chkBotao.add_CheckedChanged($habilitar)

    $atualizarEstado = {
        $lblEstado.Text = if ($script:pausado) { 'pausado' }
            elseif (-not $chkBotao.Checked -and -not [LogiSmallButton]::Running) { 'desligado' }
            else { [LogiSmallButton]::Estado }
    }
    & $atualizarEstado
    $relogio = New-Object System.Windows.Forms.Timer
    $relogio.Interval = 1000
    $relogio.add_Tick($atualizarEstado)
    $relogio.Start()

    $btnSalvar.add_Click({
        $nova = Copy-Config $script:config
        $nova.MiddleClick.Enabled = $chkMeio.Checked
        $nova.MiddleClick.Keys = $cbMeio.Text.Trim().ToUpperInvariant()
        $nova.MiddleClick.OnlyProcess = $txtPrograma.Text.Trim()
        $nova.ScrollAccel.Enabled = $chkRol.Checked
        $nova.ScrollAccel.MaxFactor = [int]$numFator.Value
        $nova.ScrollAccel.FastMs = [int]$trkVel.Value
        $nova.SmallButton.Enabled = $chkBotao.Checked
        $nova.SmallButton.Keys = $cbBotao.Text.Trim().ToUpperInvariant()

        foreach ($par in @(@($cbMeio, 'do botão do meio'), @($cbBotao, 'do botão pequeno'))) {
            try { [void](ConvertTo-TeclasVirtuais $par[0].Text) }
            catch {
                [void][System.Windows.Forms.MessageBox]::Show($f,
                    ('Atalho ' + $par[1] + ' inválido: ' + $_.Exception.Message + "`n`n" +
                     'Use teclas separadas por "+", por exemplo CTRL+W, CTRL+SHIFT+T, WIN+D, F5, PLAYPAUSE.'),
                    'Atalho inválido', 'OK', 'Warning')
                $par[0].Focus()
                return
            }
        }

        try {
            Save-ConfigArquivo $nova
            Set-IniciarComWindows $chkWindows.Checked
        }
        catch {
            [void][System.Windows.Forms.MessageBox]::Show($f, ('Não consegui salvar: ' + $_.Exception.Message), 'Erro', 'OK', 'Error')
            return
        }
        $script:config = $nova
        if (-not $script:pausado) { Set-Funcoes -Config $nova }
        [MiddleClickRemap]::Log('configuracao salva e aplicada pela janela.')
        $f.DialogResult = [System.Windows.Forms.DialogResult]::OK
        $f.Close()
    })

    $script:janela = $f
    try { [void]$f.ShowDialog() }
    finally {
        $relogio.Stop(); $relogio.Dispose()
        $f.Dispose()
        $script:janela = $null
    }
}

# ---------------------------------------------------------------------------
# Sobe o remapeamento
# ---------------------------------------------------------------------------
$logPath = $null
if ($PSBoundParameters.ContainsKey('LogFile') -and -not [string]::IsNullOrWhiteSpace($LogFile)) {
    $logPath = [System.IO.Path]::GetFullPath($LogFile)
}

$sufixo = ''
if ($DryRun.IsPresent) { $sufixo += ' [DRY-RUN: nao envia o atalho]' }
if ($NoSwallow.IsPresent) { $sufixo += ' [NoSwallow: o clique do meio tambem passa]' }

$script:bandeja = $null
try {
    [MiddleClickRemap]::Start($logPath, $DryRun.IsPresent, (-not $NoSwallow.IsPresent), $TriggerOn, $HoldMilliseconds)
    Set-Funcoes -Config $config

    if ([LogiSmallButton]::Running) {
        # Da' um instante para achar o mouse, so' para a mensagem abaixo sair certa.
        $limiteBusca = (Get-Date).AddSeconds(4)
        while ([LogiSmallButton]::Estado -eq 'procurando o mouse...' -and (Get-Date) -lt $limiteBusca) {
            Start-Sleep -Milliseconds 100
        }
    }

    $m = $config.MiddleClick; $r = $config.ScrollAccel; $b = $config.SmallButton
    Write-Host ''
    if ($m.Enabled) {
        $escopo = if ($m.OnlyProcess) { "somente no programa '" + $m.OnlyProcess + "'" } else { 'em todos os programas' }
        Write-Host ('  Botao do meio -> ' + $m.Keys + ' (' + $escopo + ')') -ForegroundColor Green
    }
    else { Write-Host '  Botao do meio: desligado (clique normal).' -ForegroundColor DarkGray }
    if ($r.Enabled -and $r.MaxFactor -gt 1) {
        Write-Host ('  Rolagem: aceleracao ate ' + $r.MaxFactor + 'x (degraus a ate ' + $r.FastMs + ' ms = giro continuo).') -ForegroundColor Green
    }
    else { Write-Host '  Rolagem: sem aceleracao.' -ForegroundColor DarkGray }
    if ($b.Enabled) { Write-Host ('  Botao pequeno abaixo da roda -> ' + $b.Keys + ': ' + [LogiSmallButton]::Estado) -ForegroundColor Green }
    else { Write-Host '  Botao pequeno abaixo da roda: desligado (Visao de Tarefas).' -ForegroundColor DarkGray }
    if (-not $IgnoreConfig.IsPresent) { Write-Host ('  Configuracao: ' + $arquivoConfig) -ForegroundColor DarkGray }
    if ($logPath) { Write-Host ('  Log: ' + $logPath) -ForegroundColor DarkGray }
    if ($sufixo) { Write-Host (' ' + $sufixo) -ForegroundColor Yellow }
    if ($usarBandeja) { Write-Host '  Icone na bandeja: clique para configurar, botao direito para pausar ou sair.' -ForegroundColor DarkGray }
    Write-Host '  Pare com Ctrl+C (ou com Parar-Remap.cmd se estiver rodando sem janela).' -ForegroundColor DarkGray
    if ($MaxSeconds -gt 0) { Write-Host ('  Encerra sozinho em ' + $MaxSeconds + ' segundos.') -ForegroundColor DarkGray }
    Write-Host ''

    $limite = if ($MaxSeconds -gt 0) { (Get-Date).AddSeconds($MaxSeconds) } else { [datetime]::MaxValue }

    if ($usarBandeja) {
        Add-Type -AssemblyName System.Windows.Forms, System.Drawing
        [System.Windows.Forms.Application]::EnableVisualStyles()

        $script:iconeAtivo = New-IconeMouse $true
        $script:iconePausado = New-IconeMouse $false

        $menu = New-Object System.Windows.Forms.ContextMenuStrip
        $itemConfig = New-Object System.Windows.Forms.ToolStripMenuItem 'Configurações...'
        $itemConfig.Font = New-Object System.Drawing.Font($menu.Font, [System.Drawing.FontStyle]::Bold)
        $script:itemPausar = New-Object System.Windows.Forms.ToolStripMenuItem 'Pausar'
        $itemSair = New-Object System.Windows.Forms.ToolStripMenuItem 'Sair'
        [void]$menu.Items.Add($itemConfig)
        [void]$menu.Items.Add($script:itemPausar)
        [void]$menu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
        [void]$menu.Items.Add($itemSair)
        $itemConfig.add_Click({ Show-Configuracoes })
        $script:itemPausar.add_Click({ Switch-Pausa })
        $itemSair.add_Click({ [void]$eventoParar.Set() })

        $script:bandeja = New-Object System.Windows.Forms.NotifyIcon
        $script:bandeja.ContextMenuStrip = $menu
        $script:bandeja.add_MouseClick({
            param($s, $e)
            if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) { Show-Configuracoes }
        })
        Update-Bandeja
        $script:bandeja.Visible = $true

        # O loop de mensagens do WinForms fica com a thread principal; o relogio
        # atende a parada (Sair, Ctrl+C, Parar-Remap.cmd, -MaxSeconds) e o pedido
        # de abrir a janela vindo de uma segunda copia do script.
        $relogioPrincipal = New-Object System.Windows.Forms.Timer
        $relogioPrincipal.Interval = 250
        $relogioPrincipal.add_Tick({
            if ($eventoParar.WaitOne(0) -or (Get-Date) -ge $limite) {
                $relogioPrincipal.Stop()
                [System.Windows.Forms.Application]::ExitThread()
            }
            elseif ($eventoConfigurar.WaitOne(0)) {
                Show-Configuracoes
            }
        })
        $relogioPrincipal.Start()
        [System.Windows.Forms.Application]::Run()
    }
    else {
        # Sem bandeja (-NoTray, ou PowerShell 7 em MTA): espera em fatias curtas.
        while ((Get-Date) -lt $limite) {
            if ($eventoParar.WaitOne(200)) { break }
        }
    }

    if ($MaxSeconds -gt 0 -and (Get-Date) -ge $limite) {
        Write-Host '  Tempo esgotado: encerrando e desinstalando o hook.' -ForegroundColor DarkGray
    }
    else {
        Write-Host '  Parada pedida: encerrando.' -ForegroundColor DarkGray
    }
}
finally {
    if ($script:bandeja) { try { $script:bandeja.Visible = $false; $script:bandeja.Dispose() } catch { } }
    try { [LogiSmallButton]::Stop() } catch { }
    try { [MiddleClickRemap]::Stop() } catch { }
    try { $eventoParar.Dispose() } catch { }
    try { $eventoConfigurar.Dispose() } catch { }
    try { $mutex.ReleaseMutex() } catch { }
    try { $mutex.Dispose() } catch { }
}
