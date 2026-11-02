# Full Control: plano de produto (decisões do Edimilson, 2026-11-02)

## DECISÃO MAIS RECENTE (2026-11-02): só na rede da TV
**Agora:** ligar/controlar a TV **somente quando o celular está na rede (Wi-Fi) da TV**. Sem Hub em casa de cliente por enquanto.
**Pendência (para depois):** controlar a TV **de fora de casa** (rua). Para isso será preciso um aparelho ligado em casa (Hub; um celular Android velho carregando com o app aberto pode servir) ou a nuvem do fabricante (Samsung SmartThings). O executor em `executor/` já cobre o caso do Hub e continua valendo para a casa do Edimilson.
**Caminho técnico agora:** aplicativo no celular (Android primeiro) que fala direto com a TV. O navegador/PWA **não** consegue (precisa de conexão TLS com certificado do cliente na porta 6466). O servidor (Supabase) guarda conta, apelidos e o certificado de pareamento; a interpretação das frases (`casa_executar_frase`) já existe.
**Opções para o aplicativo (pesquisa de 2026-11-02, nada testado):**
1. Capacitor envolvendo o Task Full + plugin que roda Node no celular (Capawesome `@capawesome/capacitor-nodejs`, baseado no nodejs-mobile): reaproveita o código do executor. **Não confirmado** que `tls`/`net` funcionam lá.
2. React Native com `react-native-androidtv-remote` (existe no npm, mesmo protocolo): app separado, só controle remoto. Qualidade e manutenção não verificadas.
3. Nativo Kotlin com protobuf: mais trabalho; existe implementação de referência em Java do pareamento (mencionada no README do `androidtvremote2`).
**Próximo passo proposto:** prova de conceito que **pareia e liga a TV** (a parte difícil). O teste na TV é do Edimilson (compilar o APK por automação do GitHub, ainda não testada).


## Foco agora
**Só TV.** A primeira TV é a TCL com Google TV (Android TV Remote v2). Nada de lâmpadas, portas, janelas nem outros conectores por enquanto; eles ficam **guardados aqui**, sem construir:
- Lâmpadas, tomadas, cortinas: nuvem Tuya/Smart Life (QR code com o app do cliente). Termos comerciais da Tuya (assinatura IoT Core) ainda não confirmados.
- TVs e aparelhos Samsung: nuvem SmartThings (login Samsung, OAuth). Se o foco virar **TV Samsung**, é outro driver (protocolo `smartthings` ou Tizen); o banco já prevê `smartthings` no campo `protocolo`.
- Portas e janelas: só depois, com confirmação em dois passos e registro de quem abriu; nunca só por voz.

## Onde o cliente instala o Hub
O Hub (o executor de `full-control/executor/`) precisa ficar **ligado 24 h, na mesma rede (roteador) da TV**. O controle remoto da TV só responde dentro da rede da casa. Opções, da mais simples:
1. **Hub pronto:** mini PC ou Raspberry Pi já configurado; o cliente liga na tomada e no cabo de rede (ou Wi-Fi) e digita o código de 6 caracteres no Task Full.
2. **Instalador de um clique** num computador que fica sempre ligado (Windows/Mac).
3. **Docker** (técnicos e o Edimilson): `docker compose up -d`.
**Não** instalar o Hub no celular: o celular dorme, sai de casa e o iPhone limita rodar em segundo plano.

## O celular do cliente (Android e iPhone)
O celular é só o **controle remoto**: abre o **Task Full no navegador (PWA instalável)** e comanda; o comando passa pelo Supabase e o Hub executa. Por isso funciona igual em Samsung, Redmi (Xiaomi) e iPhone, **em casa e na rua**, sem baixar aplicativo.
- **Android (Samsung, Redmi...) primeiro:** voz pelo reconhecimento nativo do Chrome; instalar na tela inicial.
- **iPhone depois:** os botões funcionam igual; a **voz no Safari é limitada** (testar antes de prometer); instalar na tela inicial é manual (Compartilhar > Adicionar à Tela de Início); notificações push exigem a PWA instalada. App nativo (Capacitor/TWA) só se for preciso.
- Um app nativo no celular poderia falar com a TV direto **só dentro de casa** (sem Hub). Fica como ideia futura, não substitui o Hub (não funciona na rua).

## Ordem de construção (aguardando o "pode" do Edimilson)
1. **Entrada por código** (cliente não usa console nem chave): código de 6 caracteres no Task Full, o Hub troca o código pela própria chave e guarda sozinho.
2. Tela "Full Control" no Task Full: adicionar servidor, procurar TV, parear, ligar/desligar/volume/mudo/voz (imagem antes de aplicar).
3. Imagem do Hub no Docker publicada (instalação com uma linha).
4. Instalador de um clique e Hub pronto.
5. Rotinas. Depois, outros conectores.

## Pendente do Edimilson
Primeiro teste real da TV (passo a passo em `executor/LEIA-ME.md`): TV em "Consumo elevado", Hub no Docker de casa, parear e ligar.
