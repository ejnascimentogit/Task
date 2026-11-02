# Task Full para Android (com o Full Control)

Decisão do Edimilson (2026-11-02): **um só aplicativo**. O navegador não fala com a TV (precisa de conexão TLS com certificado de cliente na rede local), então o Task Full ganhou um aplicativo Android. Ele carrega o **mesmo site** (`taskfull.ejnascimento1.workers.dev`, então toda mudança publicada vale na hora, sem novo APK) e traz por dentro o motor da TV (Node no celular, plugin `@capawesome/capacitor-nodejs`, biblioteca `androidtv-remote`, lógica `../executor/src/tv-logica.js` copiada ao compilar).

No navegador (PC, iPhone) o Task Full funciona normal; a aba **Full Control** só mostra o aviso "abra pelo aplicativo Android" e o botão para baixar. A aba só aparece para quem o master liberou (recurso `full_control`, aba Usuários → Gerenciar).

## Instalar
1. No celular Android abra **https://github.com/ejnascimentogit/Task/releases/tag/taskfull-android** e baixe `taskfull.apk`.
2. Instale (permita "instalar de fontes desconhecidas"; é build de teste, não vem da loja) e entre com a sua conta do Task Full.

## Testar a TV (celular e TV no mesmo Wi-Fi)
1. Abra a aba **Full Control**. Deve mostrar "motor pronto".
2. Digite o **IP da TV** (Configurações da TV → Rede) e toque em **Diagnóstico**: a porta 6467 deve estar aberta.
3. **Parear com a TV**: a TV mostra um código de 6 caracteres (na primeira vez pode levar até 1 minuto). Digite e envie.
4. Use **Ligar / Desligar / Volume / Mudo**. Para ligar com a TV em espera: na TV, Energia → Modos de energia → Consumo elevado.
5. Se falhar: abra "Registro" na própria aba e mande o texto.

## Limites desta versão
- Só Android; app aberto (não roda em segundo plano); IP digitado à mão (sem procurar a TV sozinho); sem voz.
- O pareamento fica **no celular** (ainda não vai para o banco): trocar de celular exige parear de novo.
- **Risco ainda não verificado:** a ponte do Capacitor (plugin Node) com o site carregado por `server.url`, e o Node iniciar no aparelho. Se a aba disser "motor não iniciou", conte.
- Build de debug de ~100 MB (todas as arquiteturas); dá para reduzir depois.
- Controlar de fora de casa continua pendência.
