# Obsidian Cosmos

Your Obsidian graph, but it looks like a video game.

## What it is

Obsidian Cosmos reads `.md` files from any Obsidian vault and renders them as a live,
single-file HTML dashboard. No server, no account, no API required. Just open `cosmos.html`
in any browser.

## Drop-in & open (12 steps)

1. Download `cosmos.html` and keep it in a folder of your choice.
2. Make sure your Obsidian vault has `.md` notes with `[[wikilinks]]`.
3. Double-click `cosmos.html` to open it in your default browser.
4. Click **Open vault…** and select the **root folder** of your Obsidian vault.
5. Wait a few seconds for the graph to render.
6. Toggle themes with the **Theme** button or press `Ctrl + T`.
7. Hover nodes to see file names and hover high-link nodes for emphasis.
8. Check the bottom-left legend to decode folder orbits and tag colors.
9. Read the bottom-right stats to confirm node/link counts.
10. For a quick sample without your real vault, click **Demo vault**.
11. To use a custom config, edit `obsidian-dashboard.json` in the same folder.
12. Keep `cosmos.html` under 500 KB — it should autoscale to small vaults too.

## Default config

```json
{
  "vaultPath": "C:/Users/seanj/iCloudDrive/iCloud~md~obsidian/SprialSecondBrain",
  "theme": "solar-system",
  "excludedFolders": [],
  "excludedExtensions": ["png","jpg","jpeg","gif","pdf","mp3","mp4","zip","obsidian.json"],
  "maxNodes": 500,
  "planetSize": 8,
  "showTags": true,
  "animate": true,
  "linkCurveStrength": 0.5
}
```

## Themes

- **Solar System** — folders become orbital rings; files are planets. Wikilinks are gravity arcs.
- **Skill Tree** — folders become branches; files are skill nodes. Hierarchy links are edges.

## Keyboard

- `Ctrl` + `T` / `Cmd` + `T` — switch themes.

## Privacy

Everything runs locally in your browser. No files leave your machine, no network calls.

## License

Proof-of-concept build for the SpiralSecondBrain project. Commercial license TBA.
