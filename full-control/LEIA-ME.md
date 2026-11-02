# Full Control: módulo de casa inteligente do Task Full

Comando de casa por botões ou voz (TV, lâmpadas, depois outros aparelhos), em casa ou na rua. O app **nunca** fala com a TV: grava um comando no Supabase e o **servidor da casa** (Windows com Docker, na mesma rede da TV) executa. Sem IA e sem tokens para comandos de casa.

## Estado (2026-11-02)
- **Banco pronto e testado** (schema `casa`, `sql/001` a `sql/003`): tabelas, regras de acesso, `casa.executar_frase`, funções do servidor da casa, aviso por Realtime, vencimento por `pg_cron` (job `casa-expirar-comandos`) e o recurso `full_control` em `recursos_liberados`. A **carga inicial** (casa, 8 cômodos, "TV do quarto") foi aplicada direto no banco e **não** fica no repositório (tem dados da rede da casa).
- **Falta:** executor em Node (passo 3), tela no app (passo 5), rotinas (passo 6).

## Decisões
- Acesso só com o recurso `full_control` (o master sempre passa). Revogar cancela os comandos pendentes.
- O schema `casa` **não é exposto** na API (isso é configuração do painel do Supabase). O app e o servidor usam funções `public.casa_*` (todas `security definer`, conferem dono ou chave por dentro). O Realtime do app funciona assim mesmo.
- O servidor da casa **não usa `service_role`**: usa uma chave própria (`casa_gerar_chave_executor`, aparece uma vez; no banco só o hash; revogável) e as funções `casa_agente_*`. É a única credencial local.
- **IP da TV não precisa ser fixo:** o executor acha a TV (último IP conhecido, nome de serviço, varredura da porta 6466) e atualiza `config.ultimo_ip`. Reservar o IP no roteador é só recomendação.
- Comando vence em 2 minutos (`expira_em`); executa uma vez só (`pendente` → `executando` atômico, `skip locked`).
- Segredos (certificado da TV) ficam em `casa.dispositivo_credenciais`, sem acesso do app (só funções do servidor).

## Funções (todas em `public`)
App (login): `casa_minha_casa()`, `casa_executar_frase(texto)`, `casa_enviar_comando(dispositivo, acao, parametros)`, `casa_status_comando(id)`, `casa_gerar_chave_executor()`.
Servidor da casa (chave): `casa_agente_sinal`, `casa_agente_pegar`, `casa_agente_resultado`, `casa_agente_estado`, `casa_agente_credencial_ler`, `casa_agente_credencial_gravar`.
Canal Realtime do servidor: broadcast `casa:<token>`, evento `novo` (o token vem em `casa_agente_sinal`). Se o aviso falhar, o servidor também consulta a cada ~15 s.

## Frases entendidas (`casa.executar_frase`)
Ação por palavras: ligar/acender, desligar/apagar, mudo/tirar o som, abaixar/aumentar volume (passos por número ou por extenso; padrão 3). Alvo = apelido mais longo contido na frase (dispositivo antes de grupo). "Abaixa o volume" e "mudo" sem dizer o aparelho funcionam se só um aparelho aceita a ação. **Limite:** frase composta executa só a primeira ação.

## Testado no banco (transação desfeita)
Frases, dono × outra pessoa, o app não lê segredos nem forja resultado, chave errada, entrega única, vencimento, campos de rede permitidos, anon não lê tabela. **Não testado:** TV real, Realtime com cliente real, tela.

## Na TV (obrigatório para ligar)
Configurações > Sistema > Energia > Modos de energia > **Consumo elevado (sempre conectado)**. Em "Consumo otimizado" a porta 6466 fecha em espera e a TV não acorda.
