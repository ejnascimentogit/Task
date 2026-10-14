# Servidor do WuzAPI (WhatsApp) — passo a passo

O Taskfull já está pronto para falar com o WuzAPI. Falta **uma máquina sempre ligada** rodando o WuzAPI, e dois segredos no Supabase. O WuzAPI é um programa em Go que mantém a sessão do WhatsApp de cada pessoa aberta; por isso **não roda** no Cloudflare Workers nem no Supabase.

> **Aviso importante.** O WuzAPI usa o protocolo do WhatsApp Web de forma **não oficial**. Isso viola os termos do WhatsApp: o número pode ser restringido ou bloqueado, principalmente se enviar muito ou para quem não espera. O Taskfull tem proteções (limite diário de 50 por pessoa, intervalo de 4 a 9 s entre envios, checagem se o número tem WhatsApp, aviso de consentimento), mas elas **diminuem** o risco, não o eliminam. Para clientes pagantes e escala, o caminho seguro é a API oficial da Meta (precisa de CNPJ). Usar com números de teste primeiro.

## 1. Máquina

- Uma VPS pequena basta (1 vCPU, 1 GB de RAM, Linux), por exemplo Hetzner, Contabo, DigitalOcean ou Oracle Cloud (camada gratuita). Custo típico: US$ 4 a 6 por mês.
- Docker e Docker Compose instalados.
- Não é necessário abrir portas se usar o Cloudflare Tunnel (passo 3).

## 2. Subir o WuzAPI (Docker)

Repositório oficial: https://github.com/asternic/wuzapi (há `docker-compose.yml` e `.env.sample`). Resumo:

```bash
git clone https://github.com/asternic/wuzapi.git && cd wuzapi
cp .env.sample .env
```

No `.env`, defina **antes de subir** (gere valores longos e aleatórios, ex.: `openssl rand -hex 32`):

```
WUZAPI_ADMIN_TOKEN=<token de admin longo e secreto>
WUZAPI_GLOBAL_ENCRYPTION_KEY=<32+ caracteres aleatórios>
WUZAPI_GLOBAL_HMAC_KEY=<32+ caracteres aleatórios>
TZ=America/Sao_Paulo
```

```bash
docker compose up -d
```

- Guarde o `WUZAPI_ADMIN_TOKEN`: sem ele não há acesso de administrador. **Nunca** coloque em arquivo do repositório nem em conversa.
- Faça backup do volume de dados do WuzAPI (guarda as sessões; se perder, todo mundo precisa ler o QR de novo).

## 3. Endereço público com HTTPS (Cloudflare Tunnel, grátis)

O Supabase precisa alcançar o WuzAPI por HTTPS. Com `cloudflared` (já usamos Cloudflare no Taskfull):

1. Zero Trust → Networks → Tunnels → criar túnel e instalar o `cloudflared` na VPS.
2. Apontar um hostname (ex.: `wuzapi.seudominio.com`) para `http://localhost:8080`.
3. Não expor a porta 8080 diretamente na internet.

(Alternativa: Caddy ou Nginx com certificado Let's Encrypt, exige domínio e portas 80/443.)

## 4. Segredos no Supabase

Supabase → Edge Functions → Secrets (projeto `painel-workspaces`):

| Segredo | Valor |
|---|---|
| `WUZAPI_URL` | `https://wuzapi.seudominio.com` (sem barra no fim) |
| `WUZAPI_ADMIN_TOKEN` | o mesmo do `.env` do WuzAPI |

Pronto: a aba WhatsApp deixa de mostrar "servidor não configurado".

## 5. Teste de fumaça (com o seu número)

1. No Taskfull, aba **Usuários** → ⚙️ Gerenciar na sua conta (o master já tem tudo) e a aba **WhatsApp** aparece.
2. Marque o aviso e clique em **Conectar WhatsApp**. Leia o QR em *WhatsApp → Aparelhos conectados → Conectar um aparelho*.
3. Envie uma mensagem **para você mesmo** (agora) e uma **programada para daqui a 2 minutos**. Confira que chegam e que a lista mostra "Enviada".
4. Teste um número sem WhatsApp (deve dar "Este número não tem WhatsApp") e o botão Desconectar.

## 6. O que conferir no primeiro teste real (a documentação do WuzAPI é inconsistente)

- **Cabeçalho do token de usuário:** o código manda `token: <token>` e, para admin, `Authorization: <admin>`. Se a tela mostrar erro 401 ao conectar, trocar em `envio.ts` (função `chamar`) para `Authorization` no token de usuário. Ao mudar, copiar o arquivo para as duas funções (`whatsapp-api` e `whatsapp-agendadas`) e publicar as duas.
- **`/session/status`:** o código espera `data.LoggedIn` e `data.Connected`; o número conectado é lido de `data.jid` (se vier com outro nome, o telefone aparece vazio, mas envia normalmente).
- **`/user/check`:** usado antes de cada envio; o JID devolvido corrige o nono dígito dos celulares.
- Versões novas do WuzAPI podem mudar campos: conferir o Swagger do próprio servidor em `/api`.

## 7. Manutenção

- Atualizar o WuzAPI de tempos em tempos (`docker compose pull && docker compose up -d`): o WhatsApp muda e versões antigas deixam de conectar.
- Se uma pessoa não consegue mais enviar e a tela diz "foi desconectado", é só conectar de novo (novo QR).
- Limite diário por pessoa: coluna `whatsapp_contas.limite_diario` (padrão 50), alterada pelo SQL Editor.
