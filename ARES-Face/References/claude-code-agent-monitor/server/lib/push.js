/**
 * @file Handles web push notifications using the `web-push` library, including generating/loading VAPID keys, sending notifications to all subscribed clients, and cleaning up invalid subscriptions. It provides a function to retrieve the public VAPID key for client registration and a function to broadcast notifications to all subscribers stored in the database.
 * @author Son Nguyen <hoangson091104@gmail.com>
 */

const webpush = require("web-push");
const path = require("path");
const fs = require("fs");

const KEYS_PATH = path.join(__dirname, "../../data/vapid-keys.json");

function loadOrCreateVapidKeys() {
  if (fs.existsSync(KEYS_PATH)) {
    return JSON.parse(fs.readFileSync(KEYS_PATH, "utf8"));
  }
  const keys = webpush.generateVAPIDKeys();
  fs.mkdirSync(path.dirname(KEYS_PATH), { recursive: true });
  fs.writeFileSync(KEYS_PATH, JSON.stringify(keys, null, 2));
  return keys;
}

const vapidKeys = loadOrCreateVapidKeys();

webpush.setVapidDetails(
  "https://github.com/hoangsonww/Claude-Code-Agent-Monitor",
  vapidKeys.publicKey,
  vapidKeys.privateKey
);

function getPublicKey() {
  return vapidKeys.publicKey;
}

async function sendPushToAll(db, title, body) {
  const subscriptions = db.prepare("SELECT * FROM push_subscriptions").all();
  if (subscriptions.length === 0) return;

  const payload = JSON.stringify({
    title,
    body,
    icon: "https://raw.githubusercontent.com/hoangsonww/Claude-Code-Agent-Monitor/main/client/public/favicon.ico",
    badge:
      "https://raw.githubusercontent.com/hoangsonww/Claude-Code-Agent-Monitor/main/client/public/favicon.ico",
    silent: false,
    sound: "default",
  });
  const results = await Promise.allSettled(
    subscriptions.map((sub) =>
      webpush.sendNotification(
        { endpoint: sub.endpoint, keys: { p256dh: sub.p256dh, auth: sub.auth } },
        payload
      )
    )
  );

  // Remove subscriptions that are gone (HTTP 410)
  for (let index = 0; index < results.length; index++) {
    const result = results[index];
    if (result.status === "rejected" && result.reason?.statusCode === 410) {
      db.prepare("DELETE FROM push_subscriptions WHERE endpoint = ?").run(
        subscriptions[index].endpoint
      );
    }
  }
}

module.exports = { getPublicKey, sendPushToAll };
