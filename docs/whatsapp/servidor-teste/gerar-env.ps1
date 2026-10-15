# Cria o arquivo .env com segredos aleatórios (só na sua máquina; o .env é ignorado pelo Git).
# Versão para Windows PowerShell (equivalente ao gerar-env.sh).
# Como rodar (dentro desta pasta):  powershell -ExecutionPolicy Bypass -File .\gerar-env.ps1
$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot
$caminho = Join-Path $PSScriptRoot '.env'
if (Test-Path -LiteralPath $caminho) {
    Write-Host 'O .env ja existe. Apague-o (Remove-Item .env) se quiser gerar de novo.'
    exit 1
}
function Novo-Hex([int]$bytes) {
    $b = New-Object byte[] $bytes
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $rng.GetBytes($b)
    $rng.Dispose()
    return (($b | ForEach-Object { $_.ToString('x2') }) -join '')
}
$admin = Novo-Hex 24
$linhas = @(
    "WUZAPI_ADMIN_TOKEN=$admin",
    "WUZAPI_GLOBAL_ENCRYPTION_KEY=$(Novo-Hex 16)",
    "WUZAPI_GLOBAL_HMAC_KEY=$(Novo-Hex 32)",
    'DB_USER=wuzapi',
    "DB_PASSWORD=$(Novo-Hex 16)",
    'DB_NAME=wuzapi',
    'DB_HOST=db',
    'DB_PORT=5432',
    'DB_SSLMODE=false',
    'WUZAPI_PORT=8080',
    'WUZAPI_ADDRESS=0.0.0.0',
    'TZ=America/Sao_Paulo',
    'SESSION_DEVICE_NAME=Taskfull',
    'WUZAPI_AUTO_PRESENCE=unavailable',
    'LOG_LEVEL=info'
)
# UTF-8 sem BOM e com quebra de linha simples (o BOM ou o CRLF podem quebrar o primeiro item do .env no Docker)
$utf8SemBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($caminho, (($linhas -join "`n") + "`n"), $utf8SemBom)
Write-Host 'Pronto: .env criado.'
Write-Host ''
Write-Host 'Copie o valor abaixo para o segredo WUZAPI_ADMIN_TOKEN no Supabase (Edge Functions > Secrets).'
Write-Host 'Ele so aparece aqui, no seu terminal. Nao cole em chat, e-mail ou arquivo do repositorio:'
Write-Host ''
Write-Host $admin
