---
name: opch-webtop
description: Use the shared webtop browser for pages that need login (LinkedIn, social, etc.); guide the user to log in in webtop when needed.
metadata: { "openclaw": { "emoji": "🖥️" } }
---

# Browser (Webtop)

You and the user share **one** browser: the **webtop**. You drive it via CDP (browser automation). The user can open the same webtop in their own browser to log in, co-work, or see what you’re doing.

## How it works

- **Webtop** = a Chromium instance (webtop + CDP) running on the stack. You control it via the browser tool (CDP). The user gets a URL (e.g. from the **Dashboard URLs** section in setup) to open the webtop in their browser — often `https://<hostname>:445/` over Tailscale.
- **Same session**: When the user logs in on a site in webtop, you see that session. When you open a page via CDP, the user can see it in webtop. One shared session.
- **Profile names**: This stack exposes the webtop CDP as **vps-chromium** (primary) and as **chrome** (so clients that default to profile=chrome connect to the same webtop). If your client uses "chrome", that is correct here — it points at the shared webtop, not a local relay.

## When the user asks to open a page (LinkedIn, BBC, social, etc.)

1. **Open the page** with the browser tool (e.g. navigate to the URL).
2. If the site **requires login** and the page shows a login screen:
   - Ask the user to **open Webtop** (they can find the link in the **Dashboard URLs** section of the setup) and **log in on that page**.
   - Once they’ve logged in, you can continue in the same session (e.g. check messages, summarise, draft replies).
3. If already logged in (or no login needed), proceed with the user’s request.

## Example workflow

**User:** “Check my messages on LinkedIn.”

1. You open the LinkedIn page (e.g. linkedin.com/messaging or linkedin.com).
2. If the page shows **login** or “Sign in”:  
   *“I’ve opened LinkedIn. It’s asking for login. Please open Webtop (link in Dashboard URLs in setup), go to the LinkedIn tab, and log in. Tell me when you’re in and I’ll check your messages.”*
3. Once the user has logged in in webtop, you use the same session to open or refresh the messages page and perform the request (e.g. summarise messages, list conversations).

Same idea for other sites (BBC, social media, work apps): open the page, if login is needed ask the user to log in in webtop, then continue.

## Rules

- Do **not** ask the user for their password or to paste credentials into chat. They log in **in webtop** in their browser.
- Point them to **Webtop** / **Dashboard URLs** in setup when they need to log in or co-work.
- After they log in in webtop, you can use the browser tool on that same session to fulfil the request.
