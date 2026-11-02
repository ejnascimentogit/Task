# Servidor da casa (executor) do Full Control

Processo Node que roda no computador da sua casa (Windows com Docker, na mesma rede da TV). Ele **abre** a conexão com o Supabase (nenhuma porta no roteador), escuta "tem comando novo" e executa na TV. Só TV Android TV / Google TV por enquanto (a "TV do quarto").

## O que ele faz
- **Sinal** a cada minuto (o app mostra "servidor da casa online").
- **Pega comandos** pendentes (uma vez só, `pendente` → `executando`) por aviso de Realtime **e** por checagem de reserva a cada 15 s.
- **Executa:** `ligar`, `desligar`, `volume`, `mudo`, `descobrir` (procurar TV na rede), `iniciar_pareamento` e `enviar_codigo`.
- **Acha a TV sozinho:** último IP conhecido → varredura da rede pela porta 6466 comparando a identidade da TV (impressão digital do certificado) → Wake-on-LAN (se tiver o MAC). **IP fixo não é obrigatório.**
- **POWER alterna liga/desliga**: só manda depois de saber o estado pelo evento `powered`; se não souber, devolve erro e não manda nada.
- **Cada operação na TV roda num processo filho** que é morto no fim ou no tempo limite (a biblioteca reconecta para sempre mesmo depois do `stop()`).
- O certificado da TV vai para o banco (`casa.dispositivo_credenciais`); nada de segredo em arquivo.

## Pré-requisito na TV (obrigatório para LIGAR)
Configurações > Sistema > Energia > Modos de energia > **Consumo elevado (sempre conectado)**. No modo "Consumo otimizado" a porta 6466 fecha em espera e a TV não acorda.

## Subir (no computador da casa)
1. Pegar o código: `git clone https://github.com/ejnascimentogit/Task` (ou `git pull`) e entrar em `full-control/executor`.
2. **Gerar a chave do servidor** (aparece uma vez; no banco só fica o hash). Enquanto a tela do app não existe, no Task Full logado, abra o console do navegador (F12) e rode:
   ```js
   (await sb.rpc('casa_gerar_chave_executor')).data
   ```
   Copie o texto que começa com `fc_`. **Não cole a chave em chat nem em print.**
3. Copiar `.env.exemplo` para `.env` e preencher `FC_CHAVE=` (e `FC_SUBREDE` se a sua rede não for `192.168.1.0/24`). O `.env` fica só no computador e o Git o ignora.
4. `docker compose up -d --build` e depois `docker compose logs -f`. Você deve ver "sinal enviado; 1 dispositivo(s)".

## Testar (pelo console do Task Full, até a tela existir)
```js
const casa = (await sb.rpc('casa_minha_casa')).data; const tv = casa.dispositivos[0].id;
casa.servidor                                   // ultimo_sinal deve ser de agora
// 1) parear: a TV mostra um código de 6 caracteres
let c = (await sb.rpc('casa_enviar_comando', { p_dispositivo: tv, p_acao: 'iniciar_pareamento' })).data;
// 2) digite o código que aparece na TV
c = (await sb.rpc('casa_enviar_comando', { p_dispositivo: tv, p_acao: 'enviar_codigo', p_parametros: { codigo: 'ABC123' } })).data;
// 3) acompanhar o resultado de qualquer comando
(await sb.rpc('casa_status_comando', { p_id: c })).data
// 4) usar
await sb.rpc('casa_executar_frase', { p_texto: 'liga a TV do quarto' })
await sb.rpc('casa_executar_frase', { p_texto: 'abaixa o volume' })
await sb.rpc('casa_executar_frase', { p_texto: 'desliga a tv' })
```

## Se algo falhar
| Sintoma | Causa provável |
|---|---|
| "A chave do servidor da casa foi recusada" | chave trocada/revogada: gere outra |
| "Não encontrei a TV na rede" ao ligar | TV em "Consumo otimizado"; ou `FC_SUBREDE` errada; ou TV em outra rede/Wi-Fi |
| `descobrir` não acha a TV | TV desligada (porta 6466 fechada em espera) ou sub-rede errada |
| "A TV não reconhece mais este pareamento" | refazer `iniciar_pareamento` + `enviar_codigo` |
| "Não consegui saber se a TV está ligada" | a TV não mandou o estado; tente de novo (o executor nunca "chuta" o POWER) |
| Comando demora até ~15 s | o canal de avisos (Realtime) não conectou; a checagem de reserva cobre |

## Limites conhecidos
- **Wake-on-LAN** por broadcast provavelmente **não sai** do Docker Desktop no Windows (rede interna do Docker). Com "Consumo elevado" não precisa. Em servidor Linux, descomente `network_mode: host` no `docker-compose.yml`.
- **Busca por nome (mDNS)** não foi implementada: a descoberta é por varredura da porta 6466.
- A biblioteca `androidtv-remote` traz dependências com alertas do `npm audit` (3, incluindo 1 crítico); o executor só fala com a TV da sua rede e com o Supabase, mas vale atualizar quando a biblioteca atualizar.
- Frase composta executa só a primeira ação.

## Testes (sem TV, sem rede, sem Supabase)
`npm install && npm test` (37 testes: lógica da TV, rede/Wake-on-LAN, regras do executor, processo filho).
