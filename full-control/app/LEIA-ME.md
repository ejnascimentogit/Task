# Full Control (aplicativo Android): prova de conceito

Objetivo: **provar que o celular consegue parear e ligar a TV** (Android TV / Google TV) pela rede Wi-Fi da casa, sem Hub. Celular e TV precisam estar na **mesma rede**. Controlar de fora de casa é pendência (ver `../PLANO-PRODUTO.md`).

## Como funciona
Aplicativo Capacitor (Android) que mostra uma tela simples e roda Node dentro do celular (plugin `@capawesome/capacitor-nodejs`, Node 18). A parte Node usa a biblioteca `androidtv-remote` e a mesma lógica da TV do executor (`../executor/src/tv-logica.js`, copiada na hora de compilar). O certificado de pareamento fica **no próprio aparelho** (nesta prova de conceito ainda não vai para o servidor).

## Instalar no celular
1. No celular Android, abra a página de downloads: **https://github.com/ejnascimentogit/Task/releases/tag/full-control-poc** e baixe `full-control.apk`.
2. Toque no arquivo baixado e instale. O Android vai pedir para permitir "instalar apps desta fonte" (Chrome ou Arquivos): permita. É um app de teste, por isso não vem da loja.
3. Abra **Full Control**.

## Testar (nesta ordem)
1. **TV ligada**, tela acesa, e o celular no mesmo Wi-Fi.
2. No app, confira o **IP da TV** (Configurações da TV > Rede). Padrão: `192.168.1.212`.
3. Toque em **Diagnóstico**. Deve mostrar `porta 6467 ABERTA` (e a 6466 também, se a TV estiver ligada). Se estiverem fechadas, o problema é rede/IP/TV desligada, não o app.
4. Toque em **Parear a TV**. A TV mostra um **código de 6 caracteres**. Na primeira vez, o celular gera um certificado e **pode demorar até 1 minuto**: aguarde. Digite o código e toque em **Enviar**.
5. Com "pareado", use **Ligar / Desligar / Volume / Mudo**.
6. **Para LIGAR com a TV em espera**, na TV deixe Energia > Modos de energia em **Consumo elevado (sempre conectado)**.

## Se algo falhar
Toque em **Copiar relatório** e cole na conversa com o Claude (sem dados sensíveis: só horário, mensagens e IP da TV). Se a tela disser "parte Node não iniciou", conte; é o principal risco desta prova de conceito (o plugin Node precisa funcionar nesse modelo de celular).

## Limites desta prova de conceito
- Só Android. iPhone depois.
- O app precisa estar **aberto**; não roda em segundo plano.
- Sem login e sem servidor (o Task Full ainda não participa): o objetivo é só provar a TV.
- Sem procurar a TV sozinho: digite o IP.
- Build de **debug** (assinado com chave de teste), instalação manual.

## Para desenvolvedores
```bash
cd full-control/app
npm install
node scripts/preparar.mjs     # copia tv-logica e instala a biblioteca da TV
npm run teste                 # testa a parte Node com uma ponte de mentira
```
A compilação do APK é feita pelo GitHub Actions (`.github/workflows/full-control-apk.yml`).
