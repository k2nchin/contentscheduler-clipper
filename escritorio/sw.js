// Lo mínimo para que el navegador la considere instalable.
// No guarda nada en caché a propósito: la página siempre habla con tu motor,
// y una copia vieja daría más problemas que ventajas.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', e => e.waitUntil(self.clients.claim()));
self.addEventListener('fetch', () => {});
