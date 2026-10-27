# Faz o servidor do WhatsApp subir SOZINHO quando você liga o computador e entra no Windows. NÃO TESTADO no Windows real.
# Instalar:  powershell -ExecutionPolicy Bypass -File .\instalar-inicio-automatico.ps1
# Remover:   powershell -ExecutionPolicy Bypass -File .\instalar-inicio-automatico.ps1 -Remover
# Cria uma tarefa agendada que, ao entrar no Windows (com 1 minuto de espera) e depois a cada 15 minutos, roda o iniciar.ps1 desta pasta.
# O iniciar.ps1 só abre o Docker Desktop se estiver fechado e sobe os contêineres que estiverem parados; se já está tudo no ar, não muda nada.
param([switch]$Remover)
$ErrorActionPreference = 'Stop'
$nome = 'TaskfullServidorWhatsApp'
if ($Remover) { Unregister-ScheduledTask -TaskName $nome -Confirm:$false -ErrorAction SilentlyContinue; Write-Host 'Início automático removido.' -ForegroundColor Green; exit 0 }
if (-not (Test-Path (Join-Path $PSScriptRoot 'iniciar.ps1'))) { Write-Host 'Rode este arquivo de dentro da pasta servidor-teste (onde está o iniciar.ps1).' -ForegroundColor Red; exit 1 }
$acao = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$(Join-Path $PSScriptRoot 'iniciar.ps1')`" -SemPausa"
$gatilho = New-ScheduledTaskTrigger -AtLogOn
$gatilho.Delay = 'PT1M'
$gatilho.Repetition = (New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 15)).Repetition
$cond = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 15) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
Register-ScheduledTask -TaskName $nome -Action $acao -Trigger $gatilho -Settings $cond -Description 'Sobe o Docker e o WuzAPI do Taskfull ao entrar no Windows' -Force | Out-Null
Write-Host 'Pronto. Na próxima vez que você entrar no Windows, o servidor sobe sozinho (1 a 3 minutos).' -ForegroundColor Green
Write-Host 'Não mova nem apague esta pasta: a tarefa roda o iniciar.ps1 daqui.' -ForegroundColor Yellow
