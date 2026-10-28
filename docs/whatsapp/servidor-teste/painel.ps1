# Painel local do servidor do WhatsApp (Windows). NÃO TESTADO no Windows real (não há PowerShell no ambiente de desenvolvimento).
# Abrir:  botão direito > "Executar com o PowerShell"   (ou crie o atalho na área de trabalho: .\painel.ps1 -CriarAtalho)
# Só mostra e liga o que já existe neste PC. Não abre porta, não recebe comando da internet, não imprime segredos (.env nunca é lido).
param([switch]$CriarAtalho)
$ErrorActionPreference = 'Continue'

if ($CriarAtalho) {
  $ws = New-Object -ComObject WScript.Shell
  $lnk = $ws.CreateShortcut((Join-Path ([Environment]::GetFolderPath('Desktop')) 'Painel do WhatsApp.lnk'))
  $lnk.TargetPath = 'powershell.exe'
  $lnk.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`""
  $lnk.WorkingDirectory = $PSScriptRoot
  $lnk.Save()
  Write-Host 'Atalho "Painel do WhatsApp" criado na área de trabalho.' -ForegroundColor Green
  exit 0
}

# Precisa de administrador (reiniciar o Tailscale e o Funnel pedem isso): reabre pedindo permissão.
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) {
  Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`""
  exit 0
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
$pasta = $PSScriptRoot

# ── Os comandos de cada botão (rodam em segundo plano para a janela não travar) ──
$cmd = @{}
$cmd['situacao'] = {
  param($p); Set-Location $p
  Write-Output '== Docker =='
  docker info *> $null; if ($LASTEXITCODE -eq 0) { Write-Output 'Docker: no ar' } else { Write-Output 'Docker: PARADO (use "Ligar tudo")' }
  Write-Output "`n== Contêineres =="
  docker compose ps -a 2>&1
  Write-Output "`n== WuzAPI neste PC (127.0.0.1:8080) =="
  try { $r = Invoke-WebRequest -Uri 'http://127.0.0.1:8080/dashboard' -UseBasicParsing -TimeoutSec 6; Write-Output ('Responde: HTTP ' + $r.StatusCode) } catch { Write-Output 'NÃO responde' }
  Write-Output "`n== Tailscale =="
  tailscale status 2>&1 | Select-Object -First 6
  Write-Output "`n== Funnel =="
  $f = tailscale funnel status 2>&1 | Out-String; Write-Output $f
  $m = [regex]::Match($f, 'https://[a-z0-9\.-]+\.ts\.net')
  if ($m.Success) {
    try { $r = Invoke-WebRequest -Uri ($m.Value + '/dashboard') -UseBasicParsing -TimeoutSec 10; Write-Output ('Endereço público visto daqui: HTTP ' + $r.StatusCode) } catch { Write-Output 'Endereço público visto daqui: NÃO abre (teste também pelo celular no 4G)' }
  } else { Write-Output 'Funnel desligado.' }
}
$cmd['ligar'] = { param($p); Set-Location $p; & (Join-Path $p 'iniciar.ps1') -SemPausa 2>&1 }
$cmd['funnel'] = {
  param($p)
  tailscale funnel reset 2>&1
  tailscale funnel --bg 8080 2>&1
  Write-Output "`n-- estado agora --"
  tailscale funnel status 2>&1
}
$cmd['tailscale'] = {
  param($p)
  Restart-Service Tailscale -ErrorAction Continue 2>&1
  Start-Sleep -Seconds 15
  tailscale status 2>&1 | Select-Object -First 4
  tailscale funnel --bg 8080 2>&1
  tailscale funnel status 2>&1
}
$cmd['wuzapi'] = { param($p); Set-Location $p; docker compose restart wuzapi 2>&1; docker compose ps 2>&1 }
$cmd['logs'] = {
  param($p); Set-Location $p
  $t = docker compose logs --no-color --tail 40 wuzapi 2>&1 | Out-String
  $t = [regex]::Replace($t, '[0-9a-fA-F]{32,}', '[SEGREDO-OCULTO]')
  Write-Output $t
}
$cmd['tunel'] = {
  param($p); Set-Location $p
  $t = docker compose logs --no-color --tail 200 tunel 2>&1 | Out-String
  $m = [regex]::Matches($t, 'https://[a-z0-9-]+\.trycloudflare\.com')
  if ($m.Count) { Write-Output ('Endereço do túnel da Cloudflare (o mais recente):'); Write-Output $m[$m.Count - 1].Value } else { Write-Output 'Não achei endereço do túnel nos logs (o contêiner tunel está ligado?).' }
}

# ── Janela ──
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Painel do servidor do WhatsApp (Taskfull)'
$form.Size = New-Object System.Drawing.Size(860, 640)
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object System.Drawing.Font('Segoe UI', 10)

$caixa = New-Object System.Windows.Forms.TextBox
$caixa.Multiline = $true; $caixa.ReadOnly = $true; $caixa.ScrollBars = 'Vertical'
$caixa.Font = New-Object System.Drawing.Font('Consolas', 10)
$caixa.Location = New-Object System.Drawing.Point(12, 130); $caixa.Size = New-Object System.Drawing.Size(820, 460)
$caixa.Anchor = 'Top,Bottom,Left,Right'
$caixa.Text = 'Clique em "Ver situação" para começar.'
$form.Controls.Add($caixa)

$info = New-Object System.Windows.Forms.Label
$info.Text = 'Só liga e confere o que já existe neste PC. Nada aqui recebe comando de fora.'
$info.Location = New-Object System.Drawing.Point(12, 98); $info.AutoSize = $true
$form.Controls.Add($info)

$script:job = $null
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 700
$timer.Add_Tick({
  if ($script:job) {
    $novo = Receive-Job -Job $script:job -ErrorAction SilentlyContinue | Out-String
    if ($novo.Trim().Length) { $caixa.AppendText($novo.TrimEnd() + "`r`n") }
    if ($script:job.State -ne 'Running') {
      $novo = Receive-Job -Job $script:job -ErrorAction SilentlyContinue | Out-String
      if ($novo.Trim().Length) { $caixa.AppendText($novo.TrimEnd() + "`r`n") }
      Remove-Job -Job $script:job -Force; $script:job = $null
      $caixa.AppendText("`r`n--- terminou ---`r`n")
      foreach ($b in $botoes) { $b.Enabled = $true }
      $timer.Stop()
    }
  }
})

function Rodar([string]$nome, [string]$titulo) {
  if ($script:job) { return }
  foreach ($b in $botoes) { $b.Enabled = $false }
  $caixa.Text = "$titulo... (pode levar alguns minutos)`r`n"
  $script:job = Start-Job -ScriptBlock $cmd[$nome] -ArgumentList $pasta
  $timer.Start()
}

$defs = @(
  @('Ver situação', 'situacao', 'Verificando'),
  @('Ligar tudo', 'ligar', 'Ligando o Docker e os contêineres'),
  @('Refazer Funnel', 'funnel', 'Refazendo o Funnel'),
  @('Reiniciar Tailscale', 'tailscale', 'Reiniciando o Tailscale'),
  @('Reiniciar WuzAPI', 'wuzapi', 'Reiniciando o WuzAPI'),
  @('Ver logs do WuzAPI', 'logs', 'Lendo os logs'),
  @('Endereço do túnel', 'tunel', 'Procurando o endereço do túnel')
)
$botoes = @()
$x = 12; $y = 12; $i = 0
foreach ($d in $defs) {
  $b = New-Object System.Windows.Forms.Button
  $b.Text = $d[0]; $b.Size = New-Object System.Drawing.Size(196, 38)
  $b.Location = New-Object System.Drawing.Point($x, $y)
  $nome = $d[1]; $titulo = $d[2]
  $b.Add_Click({ param($s, $e); $d2 = $defs | Where-Object { $_[0] -eq $s.Text }; Rodar $d2[1] $d2[2] })
  $form.Controls.Add($b); $botoes += $b
  $i++; $x += 204; if ($i % 4 -eq 0) { $x = 12; $y += 46 }
}
$form.Add_FormClosing({ if ($script:job) { Stop-Job -Job $script:job -ErrorAction SilentlyContinue; Remove-Job -Job $script:job -Force -ErrorAction SilentlyContinue } })
[void]$form.ShowDialog()
