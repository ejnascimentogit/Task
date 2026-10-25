# Agente do Taskfull no PC. NÃO TESTADO no Windows real (não há PowerShell no ambiente de desenvolvimento).
# Roda a cada minuto (tarefa agendada criada por instalar-agente.ps1). Faz só duas coisas, sempre por conexão de SAÍDA:
#   1) manda um sinal "estou vivo" ao Supabase (com a hora em que o PC ligou);
#   2) se você clicou em "Ligar servidor" no Taskfull, roda o iniciar.ps1 desta pasta e devolve o resultado.
# Não executa nenhum texto nem comando que venha da internet: o único "pedido" possível é um sim/não para rodar o iniciar.ps1.
$ErrorActionPreference = 'Stop'
$VERSAO = '1'
$pastaCfg = Join-Path $env:LOCALAPPDATA 'TaskfullAgente'
$cfg = Get-Content -Raw -Path (Join-Path $pastaCfg 'config.json') | ConvertFrom-Json
$cab = @{ apikey = $cfg.anon; Authorization = "Bearer $($cfg.anon)"; 'Content-Type' = 'application/json' }
function Chamar($nome, $corpo) { Invoke-RestMethod -Method Post -Uri "$($cfg.url)/rest/v1/rpc/$nome" -Headers $cab -Body ($corpo | ConvertTo-Json -Compress) -TimeoutSec 20 }

$boot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime.ToUniversalTime().ToString('o')
try { $r = Chamar 'agente_sinal' @{ p_chave = $cfg.chave; p_pc_ligado_em = $boot; p_versao = $VERSAO } } catch { exit 0 }   # sem internet/Supabase fora: tenta no próximo minuto
if ($r.erro) { exit 0 }   # chave trocada ou removida
if (-not $r.ligar) { exit 0 }

# Pedido de "Ligar servidor": roda só o iniciar.ps1 (sem perguntas) e resume o resultado.
$texto = ''
try {
  $saida = & (Join-Path $cfg.pasta 'iniciar.ps1') -SemPausa *>&1 | Out-String
  $ok = $false
  try { $x = Invoke-WebRequest -Uri 'http://127.0.0.1:8080/dashboard' -UseBasicParsing -TimeoutSec 8; $ok = ($x.StatusCode -lt 500) } catch { }
  $texto = if ($ok) { 'Servidor ligado: o WuzAPI está respondendo.' } else { 'Rodei o iniciar.ps1, mas o WuzAPI ainda não responde. Veja o Docker Desktop.' }
  if ($saida -match 'não ficou pronto') { $texto = 'O Docker Desktop não ficou pronto (precisa de alguém logado no Windows).' }
} catch { $texto = 'Falhou ao rodar o iniciar.ps1: ' + $_.Exception.Message }
try { Chamar 'agente_resultado' @{ p_chave = $cfg.chave; p_texto = $texto } | Out-Null } catch { }
