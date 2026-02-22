# op-and-chloe

<p align="center">
  <img src="assets/logo.png" alt="Op and Chloe" width="400">
</p>

`op-and-chloe` ("openclaw-ey") is a two-instance OpenClaw stack for any VPS.

- **🐕 Op**: operator/guard instance (admin + security approvals)
- **🐯 Chloe**: friendly day-to-day assistant (safe container)
- 🖥️ Webtop Chromium + CDP proxy for browser automation
- 🔐 Passwordless setup: no secrets or passwords stored in files (Bitwarden login/unlock is interactive only)
- ❤️ Healthcheck + watchdog

## But why?

Why do you need this?  
Why not just use OpenClaw as it is?  

You can - and you should. OpenClaw is awesome.

Setting it up from start to finish can be very tedious, though. How do you securely share credentials? How do you give OpenClaw browser access - especially on a headless server? Should you use Browserless or run headless Chromium? If you can't see the browser, how do you log in? How do you troubleshoot or fix things from your phone? And how do you help someone set up OpenClaw if they're not comfortable with SSH or the command line?

I created `op-and-chloe` to make this process easier.  
It's not a framework, not a lock-in, **it's a simple wizard** to pre-configure your stack to get you started. **Once up and running, you can change it completely**.

It looks like this:

<p align="center">
  <img src="assets/wizard.png" alt="OpenClaw Setup Wizard" width="600">
</p>


**What you get out of the box:**

- **☁️ A working stack on any VPS.** I use [Hetzner](https://www.hetzner.com), it's **~$4.70/month** and runs the full stack really well - but you can use any VPS provider. See [HETZNER.md](./HETZNER.md).

- **📱 Two Telegram chats.** One for Op (approvals, stack changes); one for Chloe (where most of your conversations happen).

- **🔒 Private access via Tailscale.** Guard, worker, and Webtop are on your Tailscale network with optional HTTPS - no public ports. Use them from your phone or laptop.

- **❤️ Health Check.** Scripts to configure, verify and keep your stack healthy.

- **🔑 Secure, passwordless credentials** Pre-authenticated CLI bridge so Chloe has no access to any passwords. No secrets or passwords are stored in files on the server—Bitwarden login and unlock are interactive only.


---


## Quick start

After purchasing your VPS from a provider, SSH into your server and follow the setup wizard step-by-step. No advanced technical skills required - just run each guided step **in order**. The wizard makes it easy: after each action, you’ll return to the menu so you can check your progress before moving on.

```bash
git clone https://github.com/mere/op-and-chloe.git
cd op-and-chloe
sudo ./setup.sh
```

<p align="center">
  <img src="assets/highfive.png" alt="OpenClaw Setup Wizard" height="300">
</p>
That's it!
It takes about 20 minutes to follow the steps and your `AI personal assistant` is ready! ✨

## How to update

To update your op-and-chloe stack: run `git pull`, then run the setup again. The wizard will show you if anything needs updating.

```bash
cd op-and-chloe   # or wherever you cloned the repo
git pull
sudo ./setup.sh
```

# Components

The stack consists of:
- **Three Docker containers:**
  - **🐕 Op**: the privileged guardian, keeps your stack safe and brokers privileged actions.
  - **🐯 Chloe**: your daily OpenClaw assistant.
  - **🖥️ Webtop browser**: provides a shared browser for both you and Chloe, enabling secure co-working even on a headless server.
- **🔗 Bridge scripts:** Lightweight scripts connect Chloe and Op, letting Op securely handle secrets and privileged commands for Chloe—without exposing credentials.

**Technical overview**

- **Two-instance OpenClaw on one VPS:**
  - **Chloe (worker):** Handles day-to-day tasks — chat, browser, drafting, etc.
  - **Op (guard):** Privileged control-plane — host control and secret broker.

- **Design principles:**
  - User-facing automation runs in the worker.
  - Privileged access is isolated and policy-gated in the guard.
  - Tailscale/SSH-first architecture for secure remote usage.
  - State is managed via Git and Docker Compose.

- **Containers:**
  - `${INSTANCE}-openclaw-gateway` — worker, exposes port `:18789`
  - `${INSTANCE}-openclaw-guard` — guard, exposes port `:18790` on loopback
  - `${INSTANCE}-browser` — webtop with Chromium CDP

- **Secrets flow:**  
  Bitwarden CLI resides in the guard. Himalaya and M365 run in the worker and fetch secrets securely via a socket-based bridge:
  ```
  scripts/worker/bridge.sh  →  scripts/guard/
  ```

- **Scripts layout:**
  - `scripts/guard/` — entrypoint, bridge server, policy logic, `bw-with-session`
  - `scripts/worker/` — bridge client, `bw`, `m365`, email/O365 setup
  - `scripts/host/` — setup, sync, CDP watchdog  
    (See `scripts/README.md` for details.)

- **Security:**  
  - Worker has **no break-glass path** for privileged access.
  - Guard has Docker socket and repo access.
  - Bridge only allows policy-allowlisted commands (e.g. `bw-with-session`), with **no interactive approval flow**.

```mermaid
flowchart LR
  U[User Telegram] --> W["Chloe / Worker :18789"]
  U --> G["Op / Guard :18790 loopback"]

  W --> B[Webtop Chromium CDP]
  W --> G
  G --> D[docker.sock]
  G --> R[repo]
  G --> S[Bitwarden]
  subgraph VPS
    W
    G
    B
    D
    R
  end
```

Secret flow: Worker → Guard (bridge) → Bitwarden; guard fetches secrets JIT and returns sanitized results. Host commands: `sudo /opt/op-and-chloe/start.sh`, `healthcheck.sh`, `stop.sh`.


---

<p align="center">
  <img src="assets/chloe.png" alt="OpenClaw Setup Wizard" height="200">
</p>

### 1. Chloe

**Chloe** *(claw-y)* is your first OpenClaw instance.  
(You can name her/him/they/it anything; it will ask for a name once it's up and running. 😊)

This is your main AI you'll be chatting with every day. Your personal assistant, trainer, coach, friend, AI employee - configure it in any way you like, even set up multiple agents.  
On the tech side, it's a standard OpenClaw installation: you can add/install/tweak/configure anything you like. Install all those funky skills, get messy! It's the OpenClaw you know and love.

But things can - and will break. Configs drift, cryptic errors appear, and some fixes can't be done in a Telegram chat. You'd have to SSH in and fix things by hand. There's also security: do you want this volatile instance to hold all your credentials? What if you install something sketchy?

This is where Op comes in:

---
<p align="center">
  <img src="assets/op.png" alt="OpenClaw Setup Wizard" height="200">
</p>

## Op

**Op** is a "small" OpenClaw instance designed to stay clean and minimal. No skills, no cron jobs, no day"-to-day tasks, no custom installs. Its job is to:
- fix things when they go wrong,
- oversee Chloe and 
- proxy pre-authenticated tools to her so she never gets to see your passwords.
- ask for your approval when Chloe tries to use a new pre-authenticated command, eg. *delete an email*.

Think of Op as your DevOps friend who can fix everything for you - including fully reconfiguring, resetting or reinstalling Chloe if needed. 

---

<p align="center">
  <img src="assets/browser.png" alt="OpenClaw Setup Wizard" height="200">
</p>

### Browser access

On a Mac mini, you can easily give OpenClaw access to a browser. On a headless VPS that's harder: headless browsers or services like Browserless can be detected by some sites, and you can't easily *see* what the agent is doing. Ideally you want to **co-work**: you log in to LinkedIn, ask the agent to check messages and draft replies; the agent fills a form, you review and submit.

op-and-chloe gives you that: a small Docker image with a browser that both you and Chloe share. You log in once; Chloe uses the same session.

---
<p align="center">
  <img src="assets/bitwarden.png" alt="OpenClaw Setup Wizard" height="200">
</p>

### Credentials

The setup script can help you create a free Bitwarden account and connect it to Op. Keep your secrets, tokens, and passwords in Bitwarden (in the cloud); **none are stored in files on the server**. You log in and unlock Bitwarden interactively in step 6; only the server URL is saved. When Chloe needs authenticated tools (mail, calendar, etc.), she requests them over an internal bridge where they're **pre-authenticated**—she never sees the secrets.

---
<p align="center">
  <img src="assets/cli.png" alt="OpenClaw Setup Wizard" height="200">
</p>

## CLI Commands

Run the setup wizard:
```bash
sudo ./setup.sh
```

Is your AI about to take over the world? Stop the containers with:
```bash
sudo ./stop.sh
```

False alarm, it was just ordering cat food? Start it with:  
> Note: This also rebuilds the container, so it's a good way to reset if things go wrong!
```
sudo ./start.sh
```


Run full health check on the stack:
```bash
sudo ./healthcheck.sh
```

To run any `openclaw` command, use:
```bash
./openclaw-guard some command
# or
./openclaw-worker some command
```


## System diagram

```mermaid
flowchart TD
    CH("<b>🐯 Chloe Bot.</b><br/><br/>Responsible for<br/>day-to-day tasks<br/>No access to credentials.")
    OP("🐕 Operator Bot<br/>Responsible for security and authentication")
    U[🥰 User]
    BW[🔐 Bitwarden]
    BR[🖥️ Webtop Browser]

    U <-->|Approves tool use| OP
    U <-->|Chats via Telegram with| CH

    OP -->|Requests credentials from| BW
    OP -->|Oversees Chloe and provides authenticated tools| CH
    U -->|Logs in to web pages like Social Media sites| BR
    CH -->|Accesses| BR
    U -->|Sets secrets in| BW

    subgraph VPS
        CH
        BR
        OP
    end
```

## Architecture
See **Technical overview** in the Components section above.


## Bridge model (BW-only)

Chloe (worker) runs **Himalaya** and **M365** locally. The bridge is used **only for Bitwarden**: she runs **`bw`** (e.g. `bw list items`, `bw get item <id>`) which executes on Op via the bridge. One-time setup scripts (scripts/worker/email-setup.py, scripts/worker/fetch-o365-config.py) use `bw` to fetch secrets from Op’s vault.

```bash
# In Chloe: Bitwarden via bridge
bw list items
bw get item <id>

# Email and M365 run locally (after one-time setup)
himalaya envelope list -a icloud -s 20 -o json
m365 mail list --top 20
```

## Docs

- **OpenClaw Web (Control UI, bind modes, Tailscale):** [https://docs.openclaw.ai/web](https://docs.openclaw.ai/web)

## Troubleshooting

**`./openclaw-guard devices list` (or worker) shows "device token mismatch":**
- The container was started with an old gateway token. Recreate so they pick up the current env file: `sudo ./stop.sh && sudo ./start.sh` (wait ~90s for gateways to be ready, then try again).

**Dashboard URLs (Guard/Worker) return HTTP 502 after `stop.sh` / `start.sh`:**
- The gateways can take 60–90 seconds to start listening. `start.sh` now waits for them before applying Tailscale serve. If you still see 502, wait a minute and refresh, or re-run: `sudo ./scripts/host/apply-tailscale-serve.sh`

**Chloe's browser tool shows wrong URL or cdpReady: false:**
- The worker state must point at the browser container's CDP endpoint. On every `start.sh` we refresh it automatically. To fix immediately: `sudo ./scripts/host/update-webtop-cdp-url.sh` (then use the worker dashboard or reconnect so Chloe picks up the new config).

**Webtop URL (https://hostname:445/) not working:**
1. Ensure the browser container is running: `docker ps | grep browser`
2. Ensure Tailscale serve is configured: `tailscale serve status`  -  you should see port 445 → 127.0.0.1:6080
3. Re-apply serve config: `sudo ./scripts/host/apply-tailscale-serve.sh`
4. For HTTPS to work, enable [HTTPS certificates](https://tailscale.com/kb/1153/enabling-https) in the admin console and run `sudo tailscale cert` on the VPS

## Security model

- **No master password on disk:** Your Bitwarden master password is never written to the host. In setup step 6 you log in and unlock once; only the Bitwarden server URL (`BW_SERVER`) and the session key from unlock are saved (in `bitwarden.env` and `guard-state/secrets/bw-session`). The guard uses that session so it can run Bitwarden CLI in any process; re-run step 6 if the vault is locked later.
- Chloe has no direct password access.
- Credentialed operations are proxied via Op-approved commands.
- Bridge mount separation:
  - Chloe gets `/var/lib/openclaw/bridge` as read-only.
  - Chloe gets `/var/lib/openclaw/bridge/inbox` as the only writable bridge path.
  - Op keeps full bridge access for approvals, policy, and audit.
- Worker bridge client: the worker container mounts the stack repo read-only and has `call` and `catalog` in PATH, so Chloe can run `call "<cmd>" --reason "..."` and `catalog` without extra setup.
- Prefer minimal, explicit command policy rules.

## License

This project is licensed under the [MIT License](LICENSE).

## Contributing

Contributions are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for how to get started.
