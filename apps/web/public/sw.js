/* Retire caches and registrations left by the removed Vanilla JS frontend. */
self.addEventListener("install", () => self.skipWaiting());
self.addEventListener("activate", (event) => {
  event.waitUntil(
    Promise.all([
      caches.keys().then((names) => Promise.all(names.map((name) => caches.delete(name)))),
      self.registration.unregister(),
      self.clients.claim(),
    ]),
  );
});
