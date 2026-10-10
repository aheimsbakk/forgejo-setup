---
topic: "Forgejo URL mismatch banner is client-side; canonical URL is the name"
importance: medium
category: warning
tags: [forgejo, root-url, dns, verification, banner]
created: 2026-10-10T01:20:18Z
model: kompis/qwen3.8-flash-next-iq3_s
---

The "configured to be served on ..." banner is injected by frontend
JavaScript comparing the browser host with the page's embedded
`appUrl`; server-rendered HTML is identical under every Host header,
so curl can never show or hide it. Verify the fix by checking the
embedded `appUrl` value and container log `AppURL(ROOT_URL)`, not by
grepping curl output for the banner. Change 30 made `https://forgejo.local/`
canonical (DOMAIN + ROOT_URL); the LAN address still serves but shows
the banner in browsers. The runner's `.runner` address was switched to
the name too.
