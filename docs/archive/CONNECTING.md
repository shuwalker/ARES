# Connecting ARES to Hermes

ARES is a viewer and control surface. The brains live in **Hermes Agent**. This
guide gets you connected in under five minutes.

## What you need

- A running Hermes Agent (`~/.hermes/` on some Mac, Linux box, or VPS). If you
  do not have one, install it from
  [nousresearch/hermes-agent](https://github.com/nousresearch/hermes-agent)
  first.
- The ARES desktop app installed and launched.
- Either SSH access to the Hermes host **or** an invite code from someone who
  already has one set up.

## Three ways to connect

### 1. Same Mac (fastest)

Use this when Hermes is already running on the Mac you are sitting at.

1. Launch ARES. The Connections tab opens automatically on first launch.
2. ARES probes `localhost:9119` and lists your local Hermes under
   **Discovered on this Mac**.
3. Click **Connect**. Done.

Under the hood ARES still goes over SSH to `localhost`, which gives it access
to the Python RPC bridge for Sessions, Skills, and Files.

### 2. Same network (Direct HTTP)

Use this when Hermes is on another machine on your LAN, VPN, or Tailnet and
its dashboard port (`9119`) is reachable.

1. In the Connections tab, look under **Discovered on your network**.
   Bonjour-advertised Hermes hosts show up here.
2. If yours is not listed, click **Set Up Manually**, choose **Direct HTTP**,
   and enter the host (e.g. `studio.local` or `100.85.249.11`).
3. Click **Connect**. No SSH config needed.

### 3. Remote machine over SSH

Use this when you reach Hermes through `ssh`.

1. Click **Set Up Manually** in the Connections tab, choose **SSH**.
2. Enter either an alias from `~/.ssh/config` (e.g. `hermes-home`) or
   host/user/port explicitly.
3. Click **Test** to verify SSH auth and `python3` availability on the host.
4. Click **Connect**. ARES starts the tunnel in the background.

## First launch walkthrough

The discovery screen has three sections:

- **Discovered on this Mac** — Hermes detected on `127.0.0.1:9119`.
- **Discovered on your network** — Hermes hosts broadcasting Bonjour on the LAN.
- **From your SSH config** — `Host` entries from `~/.ssh/config` that look like
  Hermes hosts.

If none of those apply, two buttons appear at the bottom:

- **Set Up Manually** — opens the profile editor (host/user/port/transport).
- **Paste Invite Code** — paste a code shared by a teammate.

## Sharing your Hermes with someone else

Once you have a working connection, you can share it.

1. In the Connections tab, hover the connection row.
2. Click the **Share** button (top-right of the connection row, arrow-up icon).
3. ARES shows an invite code (a base64url string). Click **Copy**.
4. Send the code over iMessage, email, or any text channel.

The recipient:

1. Launches ARES.
2. Clicks **Paste Invite Code** on the Connections tab.
3. Pastes the code and clicks **Accept**.
4. Connects normally — they still need their own SSH auth if the invite is for
   an SSH profile.

Invite codes never contain private keys or passwords.
