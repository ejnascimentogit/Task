# Instala (ou remove) o agente do Taskfull neste PC. NÃO TESTADO no Windows real.
# Instalar:  powershell -ExecutionPolicy Bypass -File .\instalar-agente.ps1
# Remover:   powershell -ExecutionPolicy Bypass -File .\instalar-agente.ps1 -Remover
# Antes: no Taskfull (conta master), aba WhatsApp > "Agente no PC" > "Gerar chave do agente". A chave aparece uma vez.
param([switch]$Remover)
$ErrorActionPreference = 'Stop'
$nomeTarefa = 'TaskfullAgente'
$pastaCfg = Join-Path $env:LOCALAPPDATA 'TaskfullAgente'
if ($Remover) {
  Unregister-ScheduledTask -TaskName $nomeTarefa -Confirm:$false -ErrorAction SilentlyContinue
  Remove-Item -Recurse -Force $pastaCfg -ErrorAction SilentlyContinue
  Write-Host 'Agente removido.' -ForegroundColor Green; exit 0
}
if (-not (Test-Path (Join-Path $PSScriptRoot 'iniciar.ps1'))) { Write-Host 'Rode este instalador de dentro da pasta servidor-teste (onde está o iniciar.ps1).' -ForegroundColor Red; exit 1 }
$segura = Read-Host 'Cole a chave do agente (gerada no Taskfull)' -AsSecureString
$chave = [System.Net.NetworkCredential]::new('', $segura).Password.Trim()
if ($chave.Length -lt 32) { Write-Host 'A chave parece curta demais. Gere de novo no Taskfull e cole inteira.' -ForegroundColor Red; exit 1 }
New-Item -ItemType Directory -Force -Path $pastaCfg | Out-Null
$cfg = @{ url = 'https://dubbmmjtbunzmdmfbbja.supabase.co'; anon = 'sb_publishable_txUpzlIpslm3DEh_GCFlBQ_WRl_BwHx'; chave = $chave; pasta = $PSScriptRoot }
$cfg | ConvertTo-Json | Set-Content -Path (Join-Path $pastaCfg 'config.json') -Encoding UTF8
icacls $pastaCfg /inheritance:r /grant:r "$($env:USERNAME):(OI)(CI)F" | Out-Null   # só o seu usuário lê a chave

$acao = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$(Join-Path $PSScriptRoot 'agente-pc.ps1')`""
$gatilho = New-ScheduledTaskTrigger -AtLogOn
$gatilho.Repetition = (New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 1)).Repetition
$cond = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 10) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
Register-ScheduledTask -TaskName $nomeTarefa -Action $acao -Trigger $gatilho -Settings $cond -Description 'Agente do Taskfull: sinal de vida e botão Ligar servidor' -Force | Out-Null
Start-ScheduledTask -TaskName $nomeTarefa
Write-Host 'Agente instalado. Em 1 a 2 minutos o Taskfull (aba WhatsApp > Agente no PC) deve mostrar "Agente ativo".' -ForegroundColor Green
Write-Host 'Não mova nem apague esta pasta: o agente roda os arquivos daqui.' -ForegroundColor Yellow
