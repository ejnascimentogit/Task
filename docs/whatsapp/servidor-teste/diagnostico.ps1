# Diagnóstico do servidor de teste do WuzAPI (Windows PowerShell). SOMENTE LEITURA: não altera nada.
# Junta o essencial para você colar no chat com o Claude. NÃO imprime o .env; esconde sequências longas de letras/números
# (tokens, chaves) e o endereço do túnel. Mesmo assim, dê uma olhada no arquivo antes de colar.
# Como rodar (dentro desta pasta):  powershell -ExecutionPolicy Bypass -File .\diagnostico.ps1
$ErrorActionPreference = 'Continue'
Set-Location -LiteralPath $PSScriptRoot
function Esconder([string]$t) {
    $t = [regex]::Replace($t, '[0-9a-fA-F]{32,}', '[SEGREDO-OCULTO]')
    $t = [regex]::Replace($t, 'https://[a-z0-9-]+\.trycloudflare\.com', 'https://[endereco-do-tunel]')
    return $t
}
function Secao([string]$titulo, [scriptblock]$comando) {
    "`n===== $titulo ====="
    try { (& $comando 2>&1 | Out-String).TrimEnd() } catch { "(falhou: $($_.Exception.Message))" }
}
$saida = @(
    "Diagnostico em $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
    (Secao 'Docker' { docker --version; docker compose version }),
    (Secao 'Contêineres (docker compose ps -a)' { docker compose ps -a }),
    (Secao 'Memória e CPU agora (docker stats)' { docker stats --no-stream --format 'table {{.Name}}\t{{.MemUsage}}\t{{.CPUPerc}}' }),
    (Secao 'wuzapi: últimas 40 linhas' { docker compose logs --no-color --tail 40 wuzapi }),
    (Secao 'db: últimas 15 linhas' { docker compose logs --no-color --tail 15 db }),
    (Secao 'tunel: últimas 15 linhas' { docker compose logs --no-color --tail 15 tunel }),
    (Secao 'Porta local responde? (http://localhost:8080/dashboard)' {
        try { $r = Invoke-WebRequest -UseBasicParsing -TimeoutSec 5 -Uri 'http://localhost:8080/dashboard'; "HTTP $($r.StatusCode)" } catch { "sem resposta: $($_.Exception.Message)" } }),
    (Secao '.env existe?' { if (Test-Path .env) { 'sim (conteúdo NÃO mostrado)' } else { 'nao' } })
) -join "`n"
$saida = Esconder $saida
$arquivo = Join-Path $PSScriptRoot 'diagnostico.txt'
[System.IO.File]::WriteAllText($arquivo, $saida + "`n", (New-Object System.Text.UTF8Encoding($false)))
$saida
Write-Host "`n--- Salvo em: $arquivo (confira antes de colar no chat) ---"
