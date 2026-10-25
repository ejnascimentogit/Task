# Liga o servidor do WhatsApp (WuzAPI) com um clique. NÃO TESTADO no Windows real (não há PowerShell no ambiente de desenvolvimento).
# Uso: botão direito neste arquivo > "Executar com o PowerShell"  (ou, no terminal, dentro desta pasta:  .\iniciar.ps1)
# Só liga o que já existe (Docker Desktop e os contêineres); não apaga nada e não mostra segredos.
$ErrorActionPreference = 'Continue'
Set-Location -Path $PSScriptRoot

function Docker-Pronto { docker info *> $null; return ($LASTEXITCODE -eq 0) }

Write-Host '1/4 Docker...' -ForegroundColor Cyan
if (-not (Docker-Pronto)) {
  $exe = "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe"
  if (Test-Path $exe) { Start-Process $exe; Write-Host '   abrindo o Docker Desktop (pode levar 1 a 2 minutos)...' }
  else { Write-Host '   Docker Desktop não encontrado. Abra-o manualmente.' -ForegroundColor Yellow }
  for ($i = 0; $i -lt 36 -and -not (Docker-Pronto); $i++) { Start-Sleep -Seconds 5 }
}
if (-not (Docker-Pronto)) { Write-Host '   O Docker não ficou pronto. Abra o Docker Desktop, espere o ícone ficar verde e rode de novo.' -ForegroundColor Red; Read-Host 'Enter para fechar'; exit 1 }
Write-Host '   Docker ok.' -ForegroundColor Green

Write-Host '2/4 Subindo os contêineres...' -ForegroundColor Cyan
docker compose up -d
docker compose ps

Write-Host '3/4 Testando o WuzAPI local...' -ForegroundColor Cyan
$ok = $false
for ($i = 0; $i -lt 12 -and -not $ok; $i++) {
  try { $r = Invoke-WebRequest -Uri 'http://127.0.0.1:8080/dashboard' -UseBasicParsing -TimeoutSec 5; if ($r.StatusCode -lt 500) { $ok = $true } } catch { Start-Sleep -Seconds 5 }
}
if ($ok) { Write-Host '   WuzAPI respondendo.' -ForegroundColor Green } else { Write-Host '   WuzAPI não respondeu. Veja:  docker compose logs --tail 50' -ForegroundColor Red }

Write-Host '4/4 Endereço público (Tailscale Funnel)...' -ForegroundColor Cyan
if (Get-Command tailscale -ErrorAction SilentlyContinue) {
  $st = tailscale funnel status 2>&1 | Out-String
  if ($st -notmatch '8080') { Write-Host '   Funnel desligado: ligando...'; tailscale funnel --bg 8080 }
  tailscale funnel status
} else { Write-Host '   Comando tailscale não encontrado (abra o app do Tailscale).' -ForegroundColor Yellow }

Write-Host ''
Write-Host 'Pronto. No Taskfull, aba WhatsApp, clique em Atualizar. Se a sessão caiu, leia o QR de novo.' -ForegroundColor Green
Read-Host 'Enter para fechar'
