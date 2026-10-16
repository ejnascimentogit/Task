# Análise da Zapia (concorrente do Assessor Pessoal)

Registrada em 2026-10-16, a pedido do Edimilson. **Fontes:** uma captura de tela da tela inicial da Zapia enviada por ele e notícias públicas. **Não consegui abrir o site da Zapia** (o ambiente de desenvolvimento bloqueia a rede), então nada aqui foi conferido no produto. Antes de decidir algo caro com base neste documento, vale entrar na Zapia, testar e atualizar esta página.

## Conclusão

- **A Zapia não substitui nada do que o Taskfull paga.** Ela é um produto de consumo concorrente, não um serviço que o Taskfull possa plugar. Não encontrei API para desenvolvedores, plano ou preço de revenda. Não conversa com o banco do Taskfull (não cria atividade nem compromisso, não lê pendências).
- **O custo que se queria cortar não vem de onde se pensava:**
  - Transcrição de áudio do Telegram: **Cloudflare Workers AI (Whisper)**, não a Anthropic.
  - Conexão com o WhatsApp (WuzAPI): sem custo de IA; o custo é só o servidor (hoje a máquina do Edimilson).
  - Anthropic: o "cérebro" do assessor (Claude Sonnet: entender o pedido, criar/remarcar/consultar) e o resumo dos e-mails (Claude Haiku). Medido: cerca de R$ 0,06 por mensagem.
- **Decisão:** manter o assessor próprio e aproveitar as **ideias** da Zapia (abaixo). Para baixar custo, usar o Haiku nas mensagens simples (já previsto no plano Básico) e manter o limite mensal por pessoa e o medidor.

## O que é a Zapia (notícias)

- Assistente pessoal de IA da América Latina, **gratuito para o usuário**, mais de 6 milhões de pessoas, com mais de 20 funções. Captou rodadas de investimento (inclusive com a Prosus) para fortalecer o app próprio e a versão "Zapia Max", mais autônoma (navegar em sites, reservas online).
- **Mudança recente:** deixou de responder direto no WhatsApp e hoje tem **app próprio** e um **conector de WhatsApp**, acionado com "@zapia" em conversas.
- **Regra da Meta:** a partir de 15/01/2026 a Meta baniu chatbots de IA de **uso geral** da API Business do WhatsApp. A Zapia contesta no Cade. Isso é um alerta para o plano de WhatsApp oficial do Taskfull (ver riscos).

Links: [Startups.com.br: Como está a Zapia depois das mudanças nas regras do WhatsApp](https://startups.com.br/negocios/inteligencia-artificial/como-esta-a-zapia-depois-das-mudancas-nas-regras-do-whatsapp/), [Teletime: Zapia, IA que agenda serviços no WhatsApp](https://teletime.com.br/03/06/2025/zapia-ia-que-agenda-servicos-whatsapp/), [Startups.com.br: Zapia levanta mais US$ 7M com Prosus](https://startups.com.br/negocios/inteligencia-artificial/zapia-levanta-mais-us-7m-com-prosus-para-fortalecer-app-proprio/).

## O que aparece na tela deles (captura de 2026-10-16)

- Menu lateral: **Novo chat**, **Agendados**, **Radar**, **Conectores**, botão Entrar.
- Saudação "Bom dia! Em que posso ajudar?" e campo único "Peça o que quiser".
- Lista de atalhos (modelos prontos): **Nutricionista**, **Coach de hábitos**, **Livro do mês**, **Resumo de grupos**, "Pergunte minhas necessidades e proponha formas de me ajudar" (com "Sugerir outra coisa") e "Mostre mais coisas para fazer".

## O que têm de melhor (pontos fortes)

1. **Começa sem ensinar nada:** um campo só e atalhos prontos. A pessoa não precisa saber o que pedir.
2. **O assistente propõe:** "pergunte minhas necessidades e proponha formas de me ajudar" e "mostre mais coisas para fazer" resolvem o problema da tela em branco.
3. **Agendados:** tarefas que o assistente executa sozinho em hora marcada.
4. **Radar:** acompanhar um assunto e avisar quando houver novidade.
5. **Resumo de grupos:** resumir conversas longas de grupo.
6. **Rotinas de vida:** nutricionista, hábitos, livro do mês (conteúdo recorrente, cria hábito de uso diário).
7. **Conectores:** o usuário liga as próprias contas, como já fazemos com e-mail.
8. **Está onde a pessoa já está:** WhatsApp e app.

## O que dá para aproveitar no Taskfull (ideias, nada feito)

| Ideia da Zapia | Como ficaria no Taskfull | Esforço | Custo de IA |
|---|---|---|---|
| Atalhos prontos na conversa | No Telegram, comando `/ideias` e botões ("Hoje", "Esta semana", "O que está atrasado?", "Criar lembrete") | Baixo | Zero (botões) |
| "Proponha formas de me ajudar" | `/ajuda` ou primeira conversa: o assistente pergunta o que a pessoa faz e sugere 3 rotinas | Baixo | Uma mensagem |
| Agendados | O assistente já cria compromisso; falta **ação agendada** ("todo dia 8h me mande o resumo do dia"). O "Bom dia" já existe na tela; levar para o Telegram | Médio | Pequeno por envio (sem IA se for só montar o resumo) |
| Radar | Avisar quando um cliente passa do prazo de re-contato ou uma pendência vence (os dados já existem; sem IA) | Médio | Zero |
| Resumo de grupos | Só faria sentido lendo o WhatsApp, que está **fora do escopo** (decidido) | Alto | Alto |
| Coach de hábitos | Rotina recorrente com lembrete diário e marcação "fiz" (usa Atividades repetidas) | Médio | Pequeno |
| Conectores | Já temos Gmail, Outlook, Yahoo; próximo: Google Agenda | Médio | Zero |
| Modelos de mensagem | Aba WhatsApp: modelos salvos pela pessoa (ideia anotada antes) | Baixo | Zero |

**Prioridade sugerida:** (1) atalhos em botões no Telegram, (2) lembretes sem IA de re-contato e pendência vencida, (3) resumo do dia enviado de manhã no Telegram, (4) modelos de mensagem do WhatsApp.

## O que NÃO copiar

- Assistente de **uso geral** ("peça o que quiser" para qualquer assunto): é o tipo de bot que a Meta baniu da API oficial do WhatsApp e gasta muito mais token. O nosso fica restrito a **agenda, tarefas, clientes e e-mail**.
- Nutricionista e coach de saúde: tema sensível; a regra do projeto é **sem diagnóstico**, e crise leva ao CVV 188.
- Resumo de grupos de WhatsApp: exigiria ler o WhatsApp, o que foi decidido não fazer.

## Riscos a acompanhar

- **Meta e IA no WhatsApp:** antes de lançar o assistente na API oficial, ler a política vigente e confirmar que um assistente de **tarefas** (não conversa geral) é permitido.
- **Concorrência:** a Zapia é gratuita para o usuário. O Taskfull se diferencia por ligar o assistente aos **dados de trabalho** (clientes, pendências, agenda, e-mail) e por ser multi-pessoa. Isso precisa aparecer na apresentação.

## Próximos passos

1. Edimilson (ou eu, com acesso à rede) entrar na Zapia e conferir: preços, existência de API/parceria, o que "Conectores" e "Radar" fazem de fato.
2. Decidir se algum item da tabela vira tarefa. Nada foi implementado por causa desta análise.
