' ---------------------------------------------------------------------------
' Iniciar-Remap.vbs
' Sobe o Remap-MiddleClickToCtrlF4.ps1 SEM janela de console.
' O -WindowStyle Hidden do powershell.exe sozinho ainda deixa piscar uma janela
' preta por um instante; lancar via WScript.Shell.Run com 0 esconde de verdade.
'
' Uso: duplo clique, ou coloque um atalho deste arquivo na pasta Inicializar.
' Para parar: use Parar-Remap.cmd.
'
' ATENCAO: este arquivo e' lido pelo WScript no codepage ANSI do sistema,
' entao tem que ficar em ASCII puro (sem acentos).
' ---------------------------------------------------------------------------
Option Explicit

Dim fso, shell, pasta, script, comando

Set fso = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")

pasta  = fso.GetParentFolderName(WScript.ScriptFullName)
script = fso.BuildPath(pasta, "Remap-MiddleClickToCtrlF4.ps1")

If Not fso.FileExists(script) Then
    MsgBox "Nao encontrei o script:" & vbCrLf & vbCrLf & script, 16, "Remap botao do meio"
    WScript.Quit 1
End If

comando = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & script & """"

' 0 = janela oculta | False = nao esperar o processo terminar
shell.Run comando, 0, False
