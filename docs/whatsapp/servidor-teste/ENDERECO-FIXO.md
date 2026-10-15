# Endereço fixo para o WuzAPI (Tailscale Funnel)

**Problema:** o túnel rápido da Cloudflare (serviço `tunel` do `docker-compose.yml`) ganha um endereço novo toda vez que reinicia, e o Taskfull (Supabase) deixa de achar o servidor até alguém atualizar o segredo `WUZAPI_URL`.

**Solução:** o **Tailscale Funnel** publica a porta 8080 da sua máquina num endereço HTTPS **fixo** (`https://nome-da-maquina.algo.ts.net`). Não precisa de IP fixo, abrir porta no roteador nem comprar domínio. Vale para Windows Home e Pro.

> Os passos abaixo foram escritos a partir da documentação pública do Tailscale (consultada por busca; as páginas não puderam ser abertas neste ambiente). Se algum menu tiver outro nome, siga o que o próprio Tailscale mostrar.
> Fontes: [tailscale funnel (CLI)](https://tailscale.com/kb/1311/funnel-cli) · [Tailscale Funnel](https://tailscale.com/kb/1223/funnel).

## 1. Instalar e entrar (uma vez)

1. Baixe o Tailscale para Windows em `https://tailscale.com/download` e instale.
2. Entre com uma conta **pessoal** (Google, Microsoft ou GitHub). Não use conta da empresa.
3. Confira no PowerShell: `tailscale status`. A máquina tem que aparecer como conectada.

## 2. Liberar o HTTPS e o Funnel na conta (uma vez)

No painel `https://login.tailscale.com/admin`:

1. **DNS**: ligue o **MagicDNS** e o **HTTPS Certificates** (o Funnel exige).
2. O Funnel precisa estar permitido na sua rede. O mais simples: rode o comando do passo 3. Se algo faltar, o próprio comando mostra um **link** para ativar; abra, confirme e rode o comando de novo.

## 3. Publicar a porta 8080

No PowerShell:

```powershell
tailscale funnel --bg 8080
tailscale funnel status
```

- `--bg` deixa rodando em segundo plano e **continua depois de reiniciar a máquina** (sem ele, o Funnel some no reinício).
- O `status` mostra o endereço, no formato `https://nome-da-maquina.algo.ts.net`. **Esse é o seu endereço fixo.** Anote.
- Funnel só aceita as portas públicas 443, 8443 e 10000. Não importa: ele publica em 443 e entrega na 8080 local.

## 4. Testar de fora

No celular, **com o Wi-Fi desligado** (4G), abra o endereço. Tem que aparecer a tela **WuzAPI Manager**. Se aparecer, está certo.

## 5. Trocar o segredo no Supabase (última vez)

Supabase → projeto `painel-workspaces` → Edge Functions → Secrets → `WUZAPI_URL` = o endereço do passo 3, com `https://` e **sem barra no fim**. Salve.

Em até 10 minutos o vigia confirma que o servidor está no ar. Na aba WhatsApp, **Atualizar** mostra na hora.

## 6. Desligar o túnel rápido

Ele não é mais necessário e só confunde:

```powershell
docker compose stop tunel
```

O `restart: unless-stopped` **respeita** a parada manual: ele não volta sozinho no reinício. (Se um dia quiser remover de vez, apague o serviço `tunel` do `docker-compose.yml`.)

## Depois de reiniciar a máquina

1. Faça login no Windows (o Docker e o Tailscale abrem sozinhos).
2. `docker compose ps`: `wuzapi` e `db` em "running".
3. `tailscale funnel status`: o endereço tem que aparecer. Se estiver vazio, rode `tailscale funnel --bg 8080` de novo.
4. O endereço é o mesmo. **Nenhuma troca no Supabase.**

## Cuidados

- **O endereço é público.** Qualquer pessoa na internet que o conheça vê a tela de login do WuzAPI; só o **token de admin** protege. Mantenha o token forte, nunca o cole em chat ou print, e troque se vazar (`gerar-env.ps1` + `docker compose up -d --force-recreate wuzapi`).
- **Não use para produção com clientes pagantes.** O Funnel tem limites de uso e a máquina é pessoal. Quando o produto evoluir, o caminho é uma VPS (os mesmos arquivos servem).
- **Máquina ligada e sem dormir.** Se ela desligar ou suspender, o WhatsApp para até voltar; mensagens programadas esperam apenas 3 tentativas de 30 min (ainda sem os prazos de 24 h/1 h).
- **Para desligar o Funnel:** `tailscale funnel --bg 8080 off` (repita os mesmos parâmetros do comando de ligar).
