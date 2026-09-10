#Requires -Version 5.1
<#
.SYNOPSIS
    Remapeia o botao do meio do mouse para o atalho CTRL+F4, globalmente.

.DESCRIPTION
    Instala um hook de mouse de baixo nivel (WH_MOUSE_LL) via P/Invoke, sem nenhuma
    dependencia externa: roda em qualquer Windows com o powershell.exe nativo.

    Comportamento:
      - O CLIQUE do botao do meio (WM_MBUTTONDOWN / WM_MBUTTONUP / WM_MBUTTONDBLCLK)
        e' suprimido e substituido por CTRL+F4.
      - A ROLAGEM continua intacta: WM_MOUSEWHEEL (0x020A) nunca e' tocada, passa
        direto pelo CallNextHookEx. O "autoscroll" (a cruzinha que aparece ao apertar
        a roda) e' disparado pelo CLIQUE, entao ele sai de cena junto.
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

.EXAMPLE
    .\Remap-MiddleClickToCtrlF4.ps1
    Remapeamento global, em primeiro plano. Pare com Ctrl+C.

.EXAMPLE
    .\Remap-MiddleClickToCtrlF4.ps1 -OnlyProcess pje1g
    Somente no programa pje1g.exe.

.EXAMPLE
    .\Remap-MiddleClickToCtrlF4.ps1 -DryRun -LogFile "$env:TEMP\remap.log"
    Testa o hook sem enviar o atalho, registrando tudo no log.

.NOTES
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

    [string]$OnlyProcess,

    [int]$HoldMilliseconds = 0,

    [int]$MaxSeconds = 0
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
    Write-Warning 'O remapeamento ja esta em execucao nesta sessao. Nada a fazer.'
    $mutex.Dispose()
    exit 0
}

# ---------------------------------------------------------------------------
# Núcleo em C#. Sintaxe compativel com C# 5 de proposito, para o mesmo texto
# compilar no Add-Type do Windows PowerShell 5.1 e no do PowerShell 7.
# ---------------------------------------------------------------------------
$codigoCSharp = @'
using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;

public static class MiddleClickRemap
{
    // ---- Constantes Win32 ----
    private const int WH_MOUSE_LL = 14;

    private const int WM_MBUTTONDOWN    = 0x0207;
    private const int WM_MBUTTONUP      = 0x0208;
    private const int WM_MBUTTONDBLCLK  = 0x0209;

    private const uint WM_QUIT     = 0x0012;
    private const uint PM_NOREMOVE = 0x0000;

    private const uint INPUT_KEYBOARD  = 1;
    private const uint KEYEVENTF_KEYUP = 0x0002;
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
    private static string _onlyProcess;
    private static bool _triggerOnDown = true;
    private static int _holdMs;

    private static StreamWriter _log;

    private static long _cliquesSuprimidos;
    private static long _ctrlF4Enviados;

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

    // -------------------------------------------------------------------
    // API publica
    // -------------------------------------------------------------------
    public static void Start(string logFile, bool dryRun, bool swallow, string onlyProcess, string triggerOn, int holdMilliseconds)
    {
        if (_running)
        {
            throw new InvalidOperationException("O remapeamento ja esta em execucao.");
        }

        _dryRun = dryRun;
        _swallow = swallow;
        _onlyProcess = string.IsNullOrEmpty(onlyProcess) ? null : NormalizeProcess(onlyProcess);
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

            bool ehDown = (mensagem == WM_MBUTTONDOWN) || (mensagem == WM_MBUTTONDBLCLK);
            bool ehUp = (mensagem == WM_MBUTTONUP);

            // Qualquer outra coisa (rolagem, botoes esquerdo/direito/laterais)
            // segue direto para o resto da cadeia, intocada.
            if (!ehDown && !ehUp)
            {
                return CallNextHookEx(_hook, nCode, wParam, lParam);
            }

            if (_onlyProcess != null && !PrimeiroPlanoCasa(_onlyProcess))
            {
                return CallNextHookEx(_hook, nCode, wParam, lParam);
            }

            Interlocked.Increment(ref _cliquesSuprimidos);

            bool dispara = (_triggerOnDown && ehDown) || (!_triggerOnDown && ehUp);
            if (dispara)
            {
                if (_dryRun)
                {
                    Log("clique do meio detectado -> DRY-RUN: enviaria CTRL+F4 (nao enviado).");
                }
                else
                {
                    Log("clique do meio detectado -> enviando CTRL+F4.");
                    ThreadPool.QueueUserWorkItem(SendWorker);
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

    // Roda no ThreadPool: fora do callback do hook.
    private static void SendWorker(object state)
    {
        try
        {
            int enviados = SendCtrlF4();
            if (enviados > 0)
            {
                Interlocked.Increment(ref _ctrlF4Enviados);
            }
            Log("SendInput retornou " + enviados.ToString() + "/4 eventos." +
                (enviados == 4 ? "" : " (atencao: envio bloqueado ou recusado pelo Windows)"));
        }
        catch (Exception ex)
        {
            Log("falha ao enviar CTRL+F4: " + ex.Message);
        }
    }

    private static int SendCtrlF4()
    {
        INPUT[] aperta = new INPUT[] { MakeKey(VK_CONTROL, false), MakeKey(VK_F4, false) };
        INPUT[] solta  = new INPUT[] { MakeKey(VK_F4, true), MakeKey(VK_CONTROL, true) };
        int tamanho = Marshal.SizeOf(typeof(INPUT));

        uint total = SendInput((uint)aperta.Length, aperta, tamanho);
        if (_holdMs > 0) Thread.Sleep(_holdMs);
        total += SendInput((uint)solta.Length, solta, tamanho);

        return (int)total;
    }

    private static INPUT MakeKey(ushort teclaVirtual, bool soltar)
    {
        INPUT entrada = new INPUT();
        entrada.type = INPUT_KEYBOARD;
        entrada.u.ki.wVk = teclaVirtual;
        entrada.u.ki.wScan = 0;
        entrada.u.ki.dwFlags = soltar ? KEYEVENTF_KEYUP : 0;
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

    private static string NormalizeProcess(string nome)
    {
        string n = nome.Trim().ToLowerInvariant();
        if (n.EndsWith(".exe")) n = n.Substring(0, n.Length - 4);
        return n;
    }

    // -------------------------------------------------------------------
    // Log
    // -------------------------------------------------------------------
    private static void Log(string mensagem)
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
'@

if (-not ('MiddleClickRemap' -as [type])) {
    Add-Type -TypeDefinition $codigoCSharp -Language CSharp -ErrorAction Stop
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

try {
    [MiddleClickRemap]::Start(
        $logPath,
        $DryRun.IsPresent,
        (-not $NoSwallow.IsPresent),
        $OnlyProcess,
        $TriggerOn,
        $HoldMilliseconds
    )

    Write-Host ''
    Write-Host '  Remapeamento ativo: botao do meio do mouse -> CTRL+F4' -ForegroundColor Green
    if ($OnlyProcess) {
        Write-Host ("  Escopo: somente o processo '" + $OnlyProcess + "'") -ForegroundColor Green
    }
    else {
        Write-Host '  Escopo: GLOBAL (todos os programas). Use -OnlyProcess <nome.exe> para restringir.' -ForegroundColor Green
    }
    Write-Host '  A rolagem (roda) continua funcionando normalmente.' -ForegroundColor DarkGray
    if ($logPath) {
        Write-Host ("  Log: " + $logPath) -ForegroundColor DarkGray
    }
    if ($sufixo) {
        Write-Host (" " + $sufixo) -ForegroundColor Yellow
    }
    Write-Host '  Pare com Ctrl+C (ou com Parar-Remap.cmd se estiver rodando sem janela).' -ForegroundColor DarkGray
    if ($MaxSeconds -gt 0) {
        Write-Host ("  Encerra sozinho em " + $MaxSeconds + " segundos.") -ForegroundColor DarkGray
    }
    Write-Host ''

    # Fica vivo. Start-Sleep responde ao Ctrl+C, e o finally abaixo desinstala o hook.
    if ($MaxSeconds -gt 0) {
        $limite = (Get-Date).AddSeconds($MaxSeconds)
        while ((Get-Date) -lt $limite) {
            Start-Sleep -Milliseconds 200
        }
        Write-Host '  Tempo esgotado: encerrando e desinstalando o hook.' -ForegroundColor DarkGray
    }
    else {
        while ($true) {
            Start-Sleep -Seconds 3600
        }
    }
}
finally {
    try { [MiddleClickRemap]::Stop() } catch { }
    try { $mutex.ReleaseMutex() } catch { }
    try { $mutex.Dispose() } catch { }
}
