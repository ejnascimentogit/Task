# Full Control: plano de produto (decisões do Edimilson, 2026-11-02)

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
