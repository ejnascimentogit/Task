// Service worker mínimo do TaskFull: deixa o app instalável e abre a casca mesmo sem rede.
// Rede primeiro (sempre pega a versão nova depois de um deploy); o cache só é usado se a rede falhar.
// Nada de dados do Supabase é guardado: só arquivos do próprio site, e só GET.
const CACHE = 'taskfull-v2';
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (e) => {
  e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k !== CACHE).map(k => caches.delete(k)))).then(() => self.clients.claim()));
});
self.addEventListener('fetch', (e) => {
  const req = e.request;
  const url = new URL(req.url);
  if (req.method !== 'GET' || url.origin !== self.location.origin) return;
  e.respondWith(
    fetch(req.mode === 'navigate' ? req.url : req, { cache: 'no-cache' }).then(res => {   // sempre confere com o servidor (nunca usa cópia velha do navegador)
      if (res.ok) { const copia = res.clone(); caches.open(CACHE).then(c => c.put(req, copia)); }
      return res;
    }).catch(() => caches.match(req).then(r => r || (req.mode === 'navigate' ? caches.match('/') : Response.error())))
  );
});
