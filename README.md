![wp-check](wp-check-banner.png)

# wp-check

![version](https://img.shields.io/badge/version-1.2-blue) ![license](https://img.shields.io/badge/license-GPLv3-green) ![bash](https://img.shields.io/badge/bash-3.2%2B-lightgrey)

A quick, outside-in security check of a WordPress site, in one bash script.
It runs anywhere bash and curl do — Linux, macOS, even your phone with [Termux](https://termux.dev/) — and answers in English or Italian.

```bash
curl -fsSLO https://raw.githubusercontent.com/SalvatoreNoschese/wp-check.sh/main/wp-check.sh && bash wp-check.sh
```

## What it checks

- **HTTPS**: http redirects to https, certificate expiry (of the host the site ends on, e.g. `www.`)
- **Security headers**: HSTS, X-Content-Type-Options, X-Frame-Options, Referrer-Policy, Permissions-Policy, Content-Security-Policy; whether `Server` or `X-Powered-By` reveal software and versions
- **Files that must not be downloadable**: `wp-config.php` and its backups, `.htaccess`, `.htpasswd`, `.env`, `.git`, logs, `readme.html`, `license.txt`
- **Directory listing** in the WordPress folders
- **Login**: where the login form is. The script first looks for it by itself on `wp-login.php` and 11 variants that often slip through (`/wp-login.php/x`, `/wp-admin/`, `/wp-admin/x`, `/wp-admin/index.php/x`, `/login`, `/admin`, `/dashboard`…), and asks for your custom login path only if `wp-login.php` does not show the login. With a hidden login:
  - none of those addresses may show the login form or lead to it — any answer is fine, 403, 404 or a redirect;
  - if a redirect leads to the hidden login, the script reports it found the login without being told;
  - no page links to it: the home page, the 404 page, the feed and every internal page reached by following the links, like a crawler would. Only real links to the site count (`https://site/path`, `//site/path`, `href="/path"`), not the same word elsewhere or `other-site/path`.
- **CAPTCHA**: whether the login form in use (standard or custom) has one (ALTCHA, reCAPTCHA, hCaptcha, Turnstile, Friendly Captcha…). Missing it is a tip, not a problem; with public usernames the hint says so. If there is one, it can also check that it really blocks (see below)
- **XML-RPC**: enabled or not, with or without pingback
- **Usernames**: exposed by the REST API (`/wp-json/wp/v2/users`) or by `?author=1`
- **WordPress version**: in the home page, the feed, the `wp-includes` files
- **Plugins**: those visible from the home page, and whether their `readme.txt` (which usually states the version) is readable

Results: **✓** fine · **✗** to fix · **!** recommended, depends on the site. Each section with a ✗ or ! ends with a short **→** hint on how to fix it.

## What it does not do

It is not a vulnerability scanner. It only sends read-only requests, the same a normal visitor would: no login attempts, no passwords, no attacks. The one exception is the optional CAPTCHA test below, which runs only after you confirm it. Use it on your own sites, or on sites you are allowed to test.

Your custom login path is never shown — not while you type it, not in the results — so screenshots are safe to share. It is checked as soon as you type it: if there is no login form there, you can type it again or skip the login checks. When nobody can answer (cron), the login checks are skipped. Skipped checks are listed after the result.

Before anything else it checks that the site answers and that it is WordPress (`admin-ajax.php` answers `400` with `0`, as only WordPress does; or WordPress paths in the home page). If not, it stops right away instead of sending dozens of requests.

### Does the CAPTCHA really block? (your own site only)

A CAPTCHA plugin can show its widget and still let the form through, for example when it only protects `wp-login.php` and the login was moved. When the login page has a CAPTCHA, the script offers to check it: it sends the form once, with a made-up user, a random password and no CAPTCHA answer. Nobody can log in, but the server logs a failed login, so it asks first (default no) and never runs from cron.

- **✓** the CAPTCHA (or the server) stops the form
- **✗** WordPress answers "this username is not registered": the form gets through without CAPTCHA. Some plugins check the CAPTCHA only for existing users; then it is a false alarm
- **!** unclear answer: test by hand

By hand, with the same request:

```bash
curl -sL --post301 --post302 -b "wordpress_test_cookie=WP%20Cookie%20check" \
  --data "log=nobody_x9k2&pwd=x&wp-submit=Log+In&testcookie=1" \
  -w '\nHTTP %{http_code} %{redirect_url}\n' "https://example.com/wp-login.php" \
  | sed 's/<[^>]*>//g' | grep -iE 'error|captcha|robot|HTTP [0-9]' | head
```

Use your login address in place of `wp-login.php` if you moved it. A CAPTCHA message (e.g. "anti-bot verification failed") or a `403` means it blocks; "the username nobody_x9k2 is not registered" means it does not.

## Usage

```bash
bash wp-check.sh                       # asks language (1 English, 2 Italiano), site and, only if needed, the custom login path
bash wp-check.sh --en example.com      # language and site from the command line
bash wp-check.sh --it esempio.it
bash wp-check.sh --no-update example.com   # skip the check for a new version
```

![wp-check](wp-check-screen.png)

Requirements: bash, curl and the usual core tools (checked at start). `openssl` is optional, for the certificate expiry.
On Termux: `pkg install curl openssl-tool`.

At start it checks whether a newer version is on GitHub (3 seconds at most, silent if offline). If there is one, it offers to update: the new file is downloaded, checked, swapped in and the script restarts with the same options. A local copy newer than GitHub's is never replaced. Run from cron, or piped with `bash <(curl …)`, it only prints a line with the download command.

At the end it offers to check another site, quit, or delete the script. Run from cron (no terminal) it just exits: the exit code is `0` when there are no problems, so it can mail you the result.

## Italiano

Controllo rapido della sicurezza di un sito WordPress, visto da fuori. Funziona ovunque ci siano bash e curl, anche dal telefono con Termux, e risponde in italiano o in inglese. Fa solo richieste in lettura, come un visitatore qualsiasi: usalo sui tuoi siti. Cerca da solo il form di accesso su `wp-login.php` e sulle varianti che spesso sfuggono (`/wp-login.php/x`, `/wp-admin/x`, `/login`…) e chiede il login personalizzato solo se `wp-login.php` non lo mostra (se è sbagliato puoi riprovare o saltare quei controlli); poi controlla che nessun indirizzo e nessun link del sito lo riveli, e se il form di accesso ha un CAPTCHA. Se c'è, propone di verificare che blocchi davvero inviando il form una volta con un utente inventato: è l'unico controllo non in sola lettura, il server lo registra come accesso fallito, quindi chiede conferma (predefinito no) e va fatto solo sul proprio sito. Per ogni problema trovato dà un breve consiglio su come risolverlo. L'indirizzo di login personalizzato non viene mai mostrato. All'avvio avvisa se su GitHub c'è una versione più recente e propone di aggiornarsi (`--no-update` per saltare il controllo). Alla fine puoi controllare un altro sito, uscire o eliminare lo script. Articolo con i dettagli: [salvatorenoschese.it/wp-check***](https://salvatorenoschese.it/wp-check-sh-controlla-la-sicurezza-del-tuo-wordpress/).

## Changelog

- **1.2** — CAPTCHA check on the login form in use (standard or custom); stronger hint when usernames are public too. Optional test, after confirmation, that the CAPTCHA really blocks (one form sent with a made-up user). Skipped checks listed together. Clearer retry prompt for the login address; header advice at the end of its section.
- **1.1** — New version check at start, with optional self-update (restarts with the same options; `--no-update` to skip it). A short hint on how to fix each problem found. Certificate expiry checked on the final host (e.g. `www.`) and working on macOS too. At the end: check another site, quit or delete the script. Login: finds the login form by itself, also on the variants (`/wp-login.php/x`, `/wp-admin/x`…); the custom path is asked only if `wp-login.php` does not show the login, and checked at once (retry or skip); looks for links to the hidden login in every page reached by following the internal links (only real links to the site, not the same word). Stops at once if the site does not answer or is not WordPress. Code comments in English only.
- **1.0** — First release.

## License

GPLv3 — © Salvatore Noschese · [salvatorenoschese.it](https://salvatorenoschese.it/)
