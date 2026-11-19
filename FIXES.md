# How to fix what wp-check finds

One section per check, in the same order as the script. Each fix is in the place that can do it:

- **WordPress** (users, version, XML-RPC, headers on pages): the ready-made mu-plugin [`fixes/wp-check-fixes.php`](fixes/wp-check-fixes.php), or the single snippet below.
- **The web server** (files, folders, https, headers on static files): rules for Apache (`.htaccess`) and nginx. A plugin cannot do these.
- **One-shot scripts** for changes made once: they run when an administrator opens the dashboard, show the result in a notice and delete themselves ([`fixes/one-shot/`](fixes/one-shot/)).

> **Before you start**
> - Make a backup, and keep FTP or file-manager access at hand: a typo in a PHP file can take the site down (white page), and the fix is deleting that file.
> - Server rules depend on the host. On some hosts `.htaccess` is ignored, on others (e.g. Altervista) it cannot be edited: there the mu-plugin is what you can do.
> - The PHP files are **edited first**: open them in a text editor and set the values at the top (switches, new names). Then **upload** them to `wp-content/mu-plugins/` (create the folder if missing) by FTP or the hosting file manager. No FTP at hand? [MustUse Manager](https://salvatorenoschese.it/mustuse-manager-wordpress-plugin/) (Full version) uploads, enables and removes mu-plugins from the dashboard.
> - After every change, run wp-check again.

**The mu-plugin in two minutes:** download [`wp-check-fixes.php`](fixes/wp-check-fixes.php), set the switches at the top (`true`/`false`), upload it to `wp-content/mu-plugins/` (create the folder if missing). It is active at once, with no activation and no settings page. To undo, delete the file.

**mu-plugin or snippet?** The snippets below are the same code as the mu-plugin, one piece at a time. Use either the mu-plugin or the snippets, not both.

---

## HTTPS

**✗ http does not redirect to https.** Many hosts have a "force HTTPS" switch in their panel (cPanel and others often have a security page with HTTPS, HSTS and XML-RPC switches): use it if there is one. Otherwise:

Apache (`.htaccess`, at the top):
```apache
RewriteEngine On
RewriteCond %{HTTPS} !=on
RewriteRule ^ https://%{HTTP_HOST}%{REQUEST_URI} [L,R=301]
```
Behind Cloudflare or another proxy this can loop (the proxy talks to the server in http): there, turn on "Always Use HTTPS" in the proxy instead.

nginx:
```nginx
server {
    listen 80;
    server_name example.com www.example.com;
    return 301 https://$host$request_uri;
}
```

**! Certificate expires soon.** Certificates from Let's Encrypt last 90 days and renew by themselves: if one is about to expire, the renewal is failing. Check the hosting panel (SSL/TLS) or `certbot renew --dry-run` on your own server.

## Security headers

**! Missing headers.** On pages, the mu-plugin (`WPCF_HEADERS`) sends them all. For every file, static ones included, the server does it:

Apache and LiteSpeed (`.htaccess`, before the `# BEGIN WordPress` block):
```apache
# /embed/ pages (a post shown inside another site) may sit in someone else's iframe: no X-Frame-Options
# there. LiteSpeed ignores SetEnvIf and "env=!…", so: a variable set by RewriteRule, SAMEORIGIN for all,
# removed where the variable is set. THE_REQUEST is the original request line, still the same after
# WordPress's internal rewrite to index.php.
<IfModule mod_rewrite.c>
    RewriteEngine On
    RewriteCond %{THE_REQUEST} \s/[^\s?]*/embed/?[\s?]
    RewriteRule ^ - [E=WPC_EMBED:1]
</IfModule>
# "set", not "always": it replaces a header WordPress or a plugin already sends, without duplicates.
<IfModule mod_headers.c>
    Header set Strict-Transport-Security "max-age=31536000"
    Header set X-Content-Type-Options "nosniff"
    Header set Referrer-Policy "strict-origin-when-cross-origin"
    Header set Permissions-Policy "camera=(), microphone=(), geolocation=(), payment=(), usb=()"
    Header set Content-Security-Policy "upgrade-insecure-requests"
    Header set X-Frame-Options "SAMEORIGIN"
    Header unset X-Frame-Options env=WPC_EMBED
    Header always unset X-Frame-Options env=WPC_EMBED
    # Both forms: "unset" for normal answers, "always unset" for the others.
    Header unset X-Powered-By
    Header always unset X-Powered-By
</IfModule>
```
With these rules on the server, or if the hosting panel already sends the headers (cPanel and others have a security page for them), set `WPCF_HEADERS` to `false` in the mu-plugin: one source for the headers is enough, two may send the same header twice.

**HSTS** tells browsers to open the site only in https for `max-age` seconds (a year here), and they remember it: turn it on only when HTTPS is there to stay. If the certificate ever goes, returning visitors cannot open the site until it is back.

nginx (inside `server { }`, plus `always` so they go on error pages too):
```nginx
add_header Strict-Transport-Security "max-age=31536000" always;
add_header X-Content-Type-Options "nosniff" always;
add_header Referrer-Policy "strict-origin-when-cross-origin" always;
add_header Permissions-Policy "camera=(), microphone=(), geolocation=(), payment=(), usb=()" always;
add_header X-Frame-Options "SAMEORIGIN" always;
add_header Content-Security-Policy "frame-ancestors 'self'; upgrade-insecure-requests" always;
```
In nginx, an `add_header` inside a `location` replaces all the ones of `server`: repeat them there if a location has its own.

The CSP above is a minimal one that rarely breaks a site. A strict CSP (which scripts, fonts, images may load) must be built for each site and tested: start with `Content-Security-Policy-Report-Only` and the browser console.

**! Server or X-Powered-By show versions.**
- Apache: `ServerTokens Prod` and `ServerSignature Off` (server config, not `.htaccess`).
- nginx: `server_tokens off;`
- PHP: `expose_php = Off` in `php.ini` (often in the hosting panel, under PHP settings).

## Files that must not be downloadable

**✗ A file is downloadable** (`wp-config.php` backups, `.env`, `.git`, logs…). First, **delete it**: backups and logs do not belong in the site folder. Then block the names, so a future copy is not exposed either:

Apache and LiteSpeed (`.htaccess`):
```apache
# Never downloadable: configuration and its copies, .ht* and .env files, logs, backups and dumps,
# readme/license/changelog files (they state versions), shell scripts. (?i): any letter case.
<FilesMatch "(?i)^(wp-config(\..*)?|wp-config-sample\.php|php\.ini|\.ht.*|\.env.*|error_log|.*\.(log|sql|bak|old|orig|swp|sh)|.*(readme|license|changelog)\.(md|txt|htm|html))$">
    Require all denied
</FilesMatch>
```
Every `readme.txt` is blocked too, plugins included: it states the installed version.

`FilesMatch` looks at file **names**, not at folders. If the site was put online with git (a `.git` folder in the site folder), the folder needs its own rule, on the path:
```apache
RedirectMatch 403 /\.git
```
Many hosts already refuse every path starting with a dot: if wp-check shows `/.git/config (403)` without this rule, the host does it.

nginx (before the `location ~ \.php$` block, or `wp-config.php` reaches PHP first):
```nginx
location ~* /(wp-config(\..*)?|wp-config-sample\.php|php\.ini|\.ht.*|\.env.*|error_log|[^/]*\.(log|sql|bak|old|orig|swp|sh)|[^/]*(readme|license|changelog)\.(md|txt|htm|html))$ {
    deny all;
}
location ~ /\.git { deny all; }   # only if the site was put online with git
```

**`debug.log`:** it fills up when `WP_DEBUG_LOG` is on in `wp-config.php`. On a live site, turn debugging off, or send the log out of the public folder:
```php
define( 'WP_DEBUG', false );
// or, to keep logging: a path outside public_html
define( 'WP_DEBUG_LOG', '/home/user/logs/wp-debug.log' );
```

**! `readme.html` and `license.txt` reachable:** the rules above block them. Deleting them is useless: every WordPress update puts them back.

## Directory listing

**✗ A folder lists its files.**

Apache (`.htaccess`): `Options -Indexes`

nginx: `autoindex off;` (the default: look for an `autoindex on;` left somewhere).

Without server access, an empty `index.php` in the folder (`<?php // Silence is golden.`) stops the listing of that folder only.

## Login and XML-RPC

**! `wp-login.php` at the standard address.** Fine with a strong password, two-factor authentication and a CAPTCHA. Moving the login (with a plugin such as WPS Hide Login) cuts the bot noise, but it is not protection by itself.

**✗ The hidden login is revealed** (a variant shows the form, a redirect leads to it, a page links to it):
- variants such as `/wp-admin/x` or `/wp-login.php/x`: check the hide-login plugin settings (some have an option for what `wp-admin` does for visitors: choose 404), or try another plugin;
- a link in a page or in the theme: remove it (menus, widgets, footer, "Log in" blocks). The script lists the pages.

**! No CAPTCHA, or the CAPTCHA does not block.** Use a CAPTCHA plugin that protects the login address you actually use: ALTCHA (no cookies, no third parties) or Cloudflare Turnstile are good choices. If you moved the login, check the plugin's option for custom login pages, then run the script's CAPTCHA test again.

**✗/! XML-RPC enabled.** Needed only by Jetpack and some remote-publishing apps. The mu-plugin (`WPCF_XMLRPC`) answers 403, removes the link to it from the page head (`EditURI`), and leaves everything alone if Jetpack is active (on the site, or network-activated on a multisite). Or on the server:

Apache: 
```apache
<Files "xmlrpc.php">
    Require all denied
</Files>
```
nginx: `location = /xmlrpc.php { deny all; }`

## Usernames

Usernames are public by design in several places, but they are half of a login. Hosting panels sometimes have a "block user enumeration" switch: it may block `?author=` but not the users API, and it may break other addresses (the WordPress export, for one). Use either it or the code below, not both. The mu-plugin (`WPCF_USERS`) closes the WordPress ways to list users, for visitors: users API (`/wp-json/wp/v2/users`, `?rest_route=`), `?author=1`, the author in oEmbed, WordPress's own author sitemap. As separate snippets:

```php
// Users API: not for visitors.
add_filter( 'rest_endpoints', static function ( $endpoints ) {
	if ( ! is_user_logged_in() && is_array( $endpoints ) ) {
		foreach ( array_keys( $endpoints ) as $route ) {
			if ( 0 === strpos( $route, '/wp/v2/users' ) ) {
				unset( $endpoints[ $route ] );
			}
		}
	}
	return $endpoints;
} );

// ?author=1: a 404 instead of the author page.
add_filter( 'request', static function ( $vars ) {
	if ( ! is_admin() && isset( $vars['author'] ) && ! isset( $vars['author_name'] ) && ! is_user_logged_in() ) {
		return [ 'error' => '404' ];
	}
	return $vars;
} );

// oEmbed: no author.
add_filter( 'oembed_response_data', static function ( $data ) {
	unset( $data['author_name'], $data['author_url'] );
	return $data;
} );

// WordPress author sitemap (/wp-sitemap-users-1.xml): off.
add_filter( 'wp_sitemaps_add_provider', static function ( $provider, $name ) {
	return 'users' === $name ? false : $provider;
}, 10, 2 );
```

**✗ Author sitemap of an SEO plugin.** In the plugin settings (menu names change between versions: look for the author archives or the sitemap options):
- **Yoast SEO**: Settings → Advanced → Author archives: turn off "Show author archives in search results" (or author archives altogether).
- **Rank Math**: Sitemap Settings → Authors: turn off "Include in Sitemap".

**! oEmbed / author pages show a name.** The public name in `/author/…/` is the author **slug**, and by default it is the login name. The blocks above stop the ways to *list* users, but the slug still shows where the site itself uses it: the author link in posts (if the theme shows it) and the CSS class of comments written by registered users (`comment-author-mario-rossi`). The fix at the root is a slug different from the login: [`fixes/one-shot/change-author-slug.php`](fixes/one-shot/change-author-slug.php). Set `$new_slug` in the file (it changes the user who opens the dashboard; set `$user_id` for another one), upload it to `mu-plugins`, open the dashboard: a notice shows the result and the file deletes itself. Login, password and posts do not change. **Recommended, not strictly needed:** with the blocks above in place and a theme that shows no author (and authors who never comment), the slug is not visible anywhere and this step is optional. It is still the only fix that does not depend on every door staying closed: a new theme or plugin can show the author again.

**✗ There is a user named "admin".** It is the first name every bot tries. **Hiding it does not help here:** bots try `admin` blindly, without looking for it, so after the mu-plugin wp-check no longer sees it, but it is still there and still guessed. With a strong password, a CAPTCHA and two-factor authentication the risk is low; renaming it takes away half of what a bot needs, so it is **recommended**. Two ways:
- **by hand:** create a new administrator with another login name, log in with it, delete `admin` and give its content to the new user (WordPress asks);
- **one-shot:** [`fixes/one-shot/rename-login.php`](fixes/one-shot/rename-login.php) renames the login in place (same user, password, posts and roles). Back up the database and **make sure you know the password**: afterwards you log in with name and password, and one-click logins (hosting panel buttons, magic links) may stop working. Then set `$new_login` in the file, upload it to `mu-plugins`, open the dashboard: a notice shows the result and the file deletes itself. Then log in again with the new name. It changes the login only: if the author address is still `/author/admin/`, the notice says so, and [`change-author-slug.php`](fixes/one-shot/change-author-slug.php) is the next step (until then wp-check still sees "admin", because the slug is what is public).

## WordPress version

**! The version is shown** (generator, feed, `?ver=` of core files). The mu-plugin (`WPCF_VERSION`) removes it from generator and feed, and turns it into a short hash in `?ver=` (still different at every update, so browser caches still renew):

```php
remove_action( 'wp_head', 'wp_generator' );
add_filter( 'the_generator', '__return_empty_string' );
```

**✗ The version has known security issues / ! it is not the latest.** Update in Dashboard → Updates, today if it is ✗. WordPress applies security releases by itself unless automatic updates were turned off: check that `wp-config.php` has no `define( 'AUTOMATIC_UPDATER_DISABLED', true );` and no `WP_AUTO_UPDATE_CORE` set to `false`. Hosting panels and management tools sometimes turn them off too.

Hiding the version only takes a hint away from bots looking for outdated sites. What protects is **keeping WordPress, themes and plugins updated** (Dashboard → Updates, or automatic updates).

**! The page cache serves an old home page.** Purge the cache (cache plugin, host panel, CDN), then check its settings: a page cache that never expires keeps serving old content, old versions included.

## Plugins

**! `readme.txt` readable.** It states the plugin version, so whoever looks for a vulnerable version finds it at once. The server rules in [Files that must not be downloadable](#files-that-must-not-be-downloadable) block every `readme.txt`. Deleting them is useless: they come back with every plugin update. Above all, **keep plugins updated** and remove the ones you do not use.

---

## Italiano

Una sezione per ogni controllo dello script, con la soluzione nel posto giusto: il **mu-plugin pronto** [`fixes/wp-check-fixes.php`](fixes/wp-check-fixes.php) per quello che può fare WordPress (nomi utente, versione, XML-RPC, intestazioni sulle pagine; si carica in `wp-content/mu-plugins/` e ha un interruttore per blocco), le **regole per il server** (`.htaccess` per Apache, nginx) per file, cartelle, https e intestazioni sui file statici, e gli **script una tantum** in [`fixes/one-shot/`](fixes/one-shot/) che si eseguono quando un amministratore apre la bacheca, mostrano l'esito in un avviso e si eliminano da soli: `change-author-slug.php` cambia lo slug dell'autore (il nome in `/author/…/`) perché non sia uguale al nome di accesso: consigliato, facoltativo se il tema non mostra l'autore e il mu-plugin chiude le altre porte; `rename-login.php` rinomina un nome di accesso come "admin" mantenendo utente, password e contenuti (non è indispensabile se password, CAPTCHA e 2FA sono a posto, ma è consigliato: nascondere i nomi non serve con "admin", perché i bot lo provano comunque alla cieca; prima assicurati di conoscere la password: dopo si entra con nome e password, e gli accessi con un clic dal pannello dell'hosting possono smettere di funzionare; solo il login: se l'indirizzo autore resta `/author/admin/`, l'avviso lo dice e il passo successivo è `change-author-slug.php`). I file PHP vanno **prima modificati** con un editor di testo (i valori in cima) e **poi caricati** in `wp-content/mu-plugins/` via FTP o con il file manager dell'hosting; senza FTP, [MustUse Manager](https://salvatorenoschese.it/mustuse-manager-wordpress-plugin/) (versione Full) li carica dalla bacheca. Prima di tutto: un backup e l'accesso FTP a portata di mano, perché un errore in un file PHP può mandare il sito in pagina bianca (si risolve eliminando il file).
