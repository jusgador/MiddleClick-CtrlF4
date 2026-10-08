# Remap botão do meio do mouse → CTRL+F4

Hook global de mouse escrito em **PowerShell puro** (C# embutido via `Add-Type`), sem
nenhuma dependência externa: roda em qualquer Windows com o `powershell.exe` nativo.
Nada de AutoHotkey, Python ou instalação de pacotes.

Pasta: `D:\dev\MiddleClick-CtrlF4`

---

## Instalação (em qualquer computador)

**Sem Git:**

1. No GitHub, clique em **Code → Download ZIP**.
2. Extraia o ZIP numa pasta **definitiva** (ex.: `C:\Ferramentas\MiddleClick-CtrlF4`) —
   o atalho de inicialização aponta para ela, então não a mova nem apague depois.
3. Dê **duplo clique em `Instalar.cmd`** e responda **S** ou **N** à pergunta
   "Iniciar automaticamente com o Windows?".

Pronto: o remapeamento já fica ligado. O `Instalar.cmd` desbloqueia os arquivos baixados,
para uma versão antiga que esteja rodando, cria (S) ou remove (N) o atalho na pasta
Inicializar e liga o remapeamento. Rode-o de novo para **atualizar** (depois de extrair
uma versão nova por cima) ou para **mudar a resposta**.

**Ou, com Git**, no lugar dos passos 1 e 2:

```powershell
git clone https://github.com/jusgador/MiddleClick-CtrlF4.git C:\Ferramentas\MiddleClick-CtrlF4
```

e depois o passo 3 (`Instalar.cmd`) do mesmo jeito. Para atualizar um clone: `git pull` na
pasta e rode o `Instalar.cmd` de novo (ele para a versão antiga e liga a nova).

Para desinstalar: rode `Instalar.cmd` respondendo **N**, depois `Parar-Remap.cmd`, e apague a pasta.

---

## O que faz

- O **clique do botão do meio** do mouse (`WM_MBUTTONDOWN` / `WM_MBUTTONUP` /
  `WM_MBUTTONDBLCLK`) é suprimido e substituído pelo atalho **CTRL+F4**.
- É **global** por padrão — vale em todos os programas.
- Por padrão o `CTRL+F4` é enviado no evento *down* (quando o botão desce).
- **Acelera a rolagem da roda** (vertical): girando devagar, cada degrau rola o normal
  (as "linhas por vez" do Windows); girando continuamente, a rolagem vai sendo
  multiplicada — 2x, 3x… até 5x por padrão. Ver [Aceleração da rolagem](#aceleração-da-rolagem).

## O que **não** faz

- **Não segura nem atrasa a rolagem.** Cada evento original da roda passa na hora,
  intacto; a aceleração só *acrescenta* um evento extra.
- **Não mexe na rolagem horizontal** (`WM_MOUSEHWHEEL`) nem na rolagem com teclas.
- **Não mexe nos botões esquerdo/direito nem nos botões laterais** (`XBUTTON`).

## Requisitos

- Windows.
- Windows PowerShell 5.1 (o `powershell.exe` que já vem no sistema) ou PowerShell 7.
- Nada para instalar. Não precisa ser administrador para o uso normal.

---

## Uso rápido

Abra um PowerShell na pasta e rode:

```powershell
cd D:\dev\MiddleClick-CtrlF4
powershell -ExecutionPolicy Bypass -File .\Remap-MiddleClickToCtrlF4.ps1
```

Fica em primeiro plano. **Pare com `Ctrl+C`.**

> Não pode ou não quer usar `-ExecutionPolicy Bypass`? Use
> `powershell -ExecutionPolicy RemoteSigned -File ...` ou rode o `.ps1` direto, se a
> sua política de execução já permitir.

---

## Rodar sem janela (e iniciar junto com o Windows)

Dê **duplo clique em `Iniciar-Remap.vbs`**. Ele sobe o `.ps1` sem nenhuma janela de
console — inclusive sem aquele piscar de janela preta que o `-WindowStyle Hidden`
sozinho às vezes deixa passar.

Como nesse modo não existe `Ctrl+C`, para parar use o **`Parar-Remap.cmd`** (duplo clique).

### Iniciar automaticamente com o Windows

Cole isto num PowerShell e rode uma vez:

```powershell
$pasta  = 'D:\dev\MiddleClick-CtrlF4'
$atalho = Join-Path ([Environment]::GetFolderPath('Startup')) 'Remap botao do meio.lnk'
$ws     = New-Object -ComObject WScript.Shell
$lnk    = $ws.CreateShortcut($atalho)
$lnk.TargetPath       = Join-Path $env:SystemRoot 'System32\wscript.exe'
$lnk.Arguments        = '"' + (Join-Path $pasta 'Iniciar-Remap.vbs') + '"'
$lnk.WorkingDirectory = $pasta
$lnk.Description      = 'Botao do meio do mouse -> CTRL+F4'
$lnk.Save()
```

Para desligar a inicialização automática, apague esse atalho da pasta Inicializar
(ou rode `explorer shell:startup`).

---

## Como parar

| Como está rodando | Como parar |
|---|---|
| Em primeiro plano (console aberto) | `Ctrl+C` no console |
| Pelo `Iniciar-Remap.vbs` (sem janela) | Duplo clique em `Parar-Remap.cmd` |
| Não lembra / travou | `Parar-Remap.cmd`, ou Gerenciador de Tarefas → `powershell.exe` |

Só existe **uma instância por vez**: o script usa um mutex (`.Local\MiddleClick-CtrlF4`),
então rodar de novo não faz nada em vez de empilhar hooks.

---

## Parâmetros

| Parâmetro | Para que serve |
|---|---|
| `-TriggerOn Down\|Up` | Manda o `CTRL+F4` quando o botão desce (padrão: `Down`) ou quando sobe. O clique inteiro é suprimido nos dois casos. |
| `-OnlyProcess <nome>` | Restringe a **um só programa** (com ou sem `.exe`, ex.: `pje1g`, `chrome`). Nos outros programas o botão do meio volta ao normal. Desligado por padrão. |
| `-DryRun` | Faz tudo igual ao modo real — **inclusive suprimir o clique do meio** — mas não envia o `CTRL+F4`. Para testar sem disparar o atalho. |
| `-LogFile <caminho>` | Grava cada evento num arquivo (uma linha por evento, com data/hora). |
| `-NoSwallow` | Diagnóstico: envia o `CTRL+F4` **e** deixa o clique do meio passar. |
| `-HoldMilliseconds <n>` | Pausa entre apertar e soltar o `CTRL+F4`. Padrão `0`. Use 30–50 só se algum programa perder o atalho. |
| `-MaxSeconds <n>` | Encerra sozinho depois de `n` segundos (padrão `0` = fica até você parar). Serve para remapear só por um tempo, e é o que os testes usam para exercitar o encerramento limpo. |
| `-NoScrollAccel` | Desliga a aceleração da rolagem (a roda volta a passar 100% intocada). |
| `-ScrollFastMs <n>` | Intervalo máximo (ms) entre dois degraus no mesmo sentido para contar como "giro contínuo". Padrão `80`. |
| `-ScrollRampNotches <n>` | Quantos degraus rápidos seguidos sobem o fator em +1. Padrão `2`. |
| `-ScrollMaxFactor <n>` | Fator máximo da aceleração. Padrão `5` (`1` = sem aceleração). |
| `-ScrollAccelInjected` | Diagnóstico/teste: acelera também rolagem **injetada** por outros programas (ver abaixo). |

### Aceleração da rolagem

A cada degrau da roda o hook olha quanto tempo passou desde o degrau anterior:

- **Mais de `ScrollFastMs` (80 ms)**, ou mudou o sentido → giro lento: fator 1x, nada
  é acrescentado. A sequência rápida zera.
- **Até `ScrollFastMs`** → giro contínuo: a sequência rápida cresce, e o fator é
  `1 + sequência / ScrollRampNotches`, limitado a `ScrollMaxFactor`.

Com os padrões: os 2 primeiros degraus rápidos rolam normal, depois 2x, 3x, 4x e, a
partir do 8º degrau seguido, 5x. Quando o fator passa de 1, o hook deixa o evento
original seguir e injeta (no `ThreadPool`, fora do callback) um evento extra com
`delta × (fator − 1)`. O extra leva uma marca no `dwExtraInfo`, e o hook ignora o que
tem essa marca, para não acelerar o próprio extra em loop.

A velocidade "lenta" é a do Windows: **Configurações → Bluetooth e dispositivos →
Mouse → Linhas para rolar por vez**. Deixe esse valor baixo (1–3) e a aceleração cuida
do resto.

**Rolagem injetada é ignorada por padrão.** Softwares de mouse (Logitech Options+, rolagem
suave etc.) às vezes injetam muitos eventos pequenos; acelerá-los multiplicaria a rolagem
de um jeito imprevisível. Só a roda física é acelerada, a menos que você passe
`-ScrollAccelInjected`.

**Para ajustar no dia a dia** (o `Iniciar-Remap.vbs` sobe o script sem argumentos):
mude os valores padrão dos parâmetros `ScrollFastMs`, `ScrollRampNotches` e
`ScrollMaxFactor` no bloco `param(...)` do `Remap-MiddleClickToCtrlF4.ps1` e reinicie
(`Parar-Remap.cmd` e depois `Iniciar-Remap.vbs`).

### Restringir a um programa específico (opcional)

```powershell
.\Remap-MiddleClickToCtrlF4.ps1 -OnlyProcess pje1g
```

O nome é o do **processo**, não o do título da janela. Para descobrir, com o programa
em foco:

```powershell
(Get-Process -Id (Get-Process | Where-Object MainWindowTitle -like '*PJe*').Id).ProcessName
```

Ou simplesmente abra o Gerenciador de Tarefas → aba Detalhes e olhe a coluna
"Nome da imagem" (sem o `.exe`).

---

## Efeitos colaterais conhecidos

Leia antes de reclamar que "quebrou o botão do meio" — tudo abaixo é consequência
direta e esperada de remapear o clique:

1. **Autoscroll não funciona mais.** A "cruzinha" de rolagem do Windows/Chrome é
   disparada pelo *clique* do meio, que agora é suprimido. A **rolagem em si continua
   funcionando** (e acelerada) — é outra mensagem do Windows (`WM_MOUSEWHEEL`).
2. **Navegadores:** "abrir link em nova aba" com o botão do meio para de funcionar, e
   o `CTRL+F4` que entra no lugar **fecha a aba atual**.
3. **Arrastar com o botão do meio** (alguns programas) deixa de funcionar.
4. **Programas abertos como administrador não recebem o `CTRL+F4`.** O Windows (UIPI)
   bloqueia injeção de input vinda de um processo de integridade menor. Se você precisa
   que funcione em cima de uma janela elevada, rode o script **também elevado**.
   Dica: o log (`-LogFile`) registra `SendInput retornou 0/4 eventos` exatamente quando
   isso acontece.
5. **Jogos com raw input** (DirectInput) não são afetados: eles não passam pelo hook de
   baixo nível, então lá o botão do meio continua original.
6. **`WIN`/`Alt`+clique** e outros atalhos de janela não são afetados.

---

## Testes

`Test-Remap.ps1` verifica a cadeia inteira **sem você precisar clicar em nada**. Ele sobe
o remapeamento num processo separado, injeta input sintético e confere seis coisas:

1. o clique do meio **não** chega na janela de teste — foi suprimido;
2. o `CTRL+F4` **chega** na janela de teste — o atalho foi enviado;
3. a **rolagem lenta chega intacta** (3 degraus espaçados = 3 × 120, sem extra);
4. a **rolagem rápida chega ampliada** (10 degraus seguidos somam mais que 1200);
5. o botão **esquerdo continua chegando** — os outros botões ficam intactos;
6. o encerramento por `-MaxSeconds` **desinstala o hook** e o processo sai sozinho,
   inclusive recuperando o mutex quando a instância anterior morreu à força.

Ele avisa antes de começar (o botão do meio fica remapeado por uns 15 segundos e o cursor
é movido), devolve o cursor ao lugar no final e não abre nada que possa ser fechado sem
querer. Sai com código `0` se passou e `1` se falhou.

Rode com `-KeepLog` para guardar os logs da execução em `%TEMP%` e poder inspecioná-los.

```powershell
cd D:\dev\MiddleClick-CtrlF4
powershell -ExecutionPolicy Bypass -File .\Test-Remap.ps1
```

---

## Solução de problemas

**O botão do meio continua igual, nada muda.**
Feche os outros remapeadores que possam estar rodando e veja o log com
`-LogFile "$env:TEMP\remap.log"`. Se o log não registra nada ao clicar, o hook não
pegou o evento.

**O clique do meio sumiu e nenhum `CTRL+F4` aparece.**
O programa em foco é elevado (item 4 acima). Rode o script elevado.

**O remapeamento para sozinho depois de um tempo.**
O Windows desinstala hooks de baixo nível cujo callback demora mais que o
`LowLevelHooksTimeout` (300 ms por padrão). Por isso o `SendInput` **nunca** roda
dentro do callback: ele vai para o `ThreadPool`. Se acontecer mesmo assim, veja
`HKEY_CURRENT_USER\Control Panel\Desktop\LowLevelHooksTimeout`.

**Aparece "O remapeamento já está em execução nesta sessão".**
É o mutex de instância única — já tem um rodando (possivelmente sem janela, iniciado
pelo VBS). Use `Parar-Remap.cmd` primeiro.

---

## Arquivos

| Arquivo | Papel |
|---|---|
| `Instalar.cmd` | Instalação em um passo: pergunta sobre iniciar com o Windows e liga o remapeamento. |
| `Remap-MiddleClickToCtrlF4.ps1` | O remapeamento em si (hook + envio do atalho). |
| `Iniciar-Remap.vbs` | Lança o `.ps1` sem janela de console. |
| `Parar-Remap.cmd` | Encerra o processo do remapeamento. |
| `Test-Remap.ps1` | Teste automatizado da cadeia completa. |

## Como funciona por dentro

- `SetWindowsHookEx(WH_MOUSE_LL)` recebe todo o mouse do sistema; o callback trata só
  `0x0207`/`0x0208`/`0x0209` e devolve `1` para suprimir. Tudo o mais vai para
  `CallNextHookEx`.
- O callback do hook é **curto de propósito**: ele só marca o evento e joga o envio para
  o `ThreadPool` (`QueueUserWorkItem`). Chamar `SendInput` dentro do callback é o
  caminho clássico para o Windows derrubar o hook por timeout.
- O loop de mensagens é um `GetMessage` **bloqueante** numa thread dedicada (o Windows só
  entrega o callback do hook para a thread que o instalou e que está bombeando
  mensagens). O `Stop()` acorda esse loop com `PostThreadMessage(WM_QUIT)`.
- O delegate do hook fica guardado num campo estático (`_proc`); sem essa raiz forte o
  GC o coleta e o callback estoura.
