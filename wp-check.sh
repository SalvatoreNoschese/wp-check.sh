#!/usr/bin/env bash
# wp-check.sh — quick outside-in security check of a WordPress site / controllo rapido della sicurezza di un sito WordPress.
# Usage / Uso:  bash wp-check.sh [--it|--en] [site]      e.g. bash wp-check.sh --en example.com
# Read-only requests, like any visitor: no login attempts, no attacks. Use it on your own sites.
# Solo richieste in lettura, come un visitatore qualsiasi: niente tentativi di accesso né attacchi. Usalo sui tuoi siti.
# v1.0 — Salvatore Noschese — https://github.com/SalvatoreNoschese/wp-check.sh — GPLv3

UA="Mozilla/5.0 (X11; Linux x86_64; rv:140.0) Gecko/20100101 Firefox/140.0"
ok=0; ko=0; warn=0

# --- Language / Lingua ---
LNG=""; S=""
for a in "$@"; do
	case "$a" in
		--it) LNG=it ;;
		--en) LNG=en ;;
		*) S="$a" ;;
	esac
done
if [[ -z "$LNG" ]]; then
	def=en; [[ "${LANG:-}" == it* ]] && def=it
	read -r -p "Language / Lingua (en/it) [$def]: " LNG
	LNG="${LNG:-$def}"
fi
[[ "$LNG" == it ]] || LNG=en
t() { [[ "$LNG" == it ]] && printf '%s' "$1" || printf '%s' "$2"; }   # t "italiano" "english"

if [[ -t 1 ]]; then G=$'\033[32m'; R=$'\033[31m'; Y=$'\033[33m'; N=$'\033[0m'; else G=; R=; Y=; N=; fi
pass() { printf '  %s✓%s %s\n' "$G" "$N" "$1"; ok=$((ok+1)); }
fail() { printf '  %s✗%s %s\n' "$R" "$N" "$1"; ko=$((ko+1)); }
hint() { printf '  %s!%s %s\n' "$Y" "$N" "$1"; warn=$((warn+1)); }
code() { curl -s -o /dev/null -A "$UA" --max-time 15 -w "%{http_code}" "$@"; }
loc()  { curl -s -o /dev/null -A "$UA" --max-time 15 -w "%{redirect_url}" "$@"; }
get()  { curl -s -L -A "$UA" --max-time 15 "$@"; }

# --- Requirements / Requisiti ---
missing=()
for cmd in curl grep sed cut tr head date sort uniq awk wc; do
	command -v "$cmd" >/dev/null || missing+=("$cmd")
done
if (( ${#missing[@]} )); then
	echo "$(t "Mancano" "Missing"): ${missing[*]}"
	echo "Termux: pkg install ${missing[*]/date/coreutils}   ·   Debian/Ubuntu: sudo apt install ${missing[*]/date/coreutils}"
	exit 2
fi
command -v openssl >/dev/null || echo "($(t "openssl non c'è: salto la scadenza del certificato" "openssl not found: certificate expiry skipped") — pkg install openssl-tool)"

# --- Site / Sito ---
[[ -z "$S" ]] && read -r -p "$(t "Sito da controllare (es. esempio.it)" "Site to check (e.g. example.com)"): " S
S="${S#http://}"; S="${S#https://}"; S="${S%%/*}"
[[ -z "$S" ]] && { t "Nessun sito indicato." "No site given."; echo; exit 2; }
# Non mostrato né mentre lo scrivi (nemmeno la lunghezza) né nei risultati: uno screenshot non deve rivelarlo.
read -r -s -p "$(t "Indirizzo di login personalizzato, se ce n'è uno (non viene mostrato), altrimenti Invio" "Custom login path, if any (it is not shown), otherwise Enter"): " LOGIN
LOGIN="${LOGIN// /}"
[[ -n "$LOGIN" ]] && echo " ✓" || echo
[[ -n "$LOGIN" && "$LOGIN" != /* ]] && LOGIN="/$LOGIN"
HIDDEN="/•••"

B="https://$S"
echo
echo "== $B"

c=$(code "$B/")
[[ "$c" == 000 ]] && { t "Il sito non risponde in HTTPS." "The site does not answer over HTTPS."; echo; exit 2; }
[[ "$c" =~ ^(200|301|302)$ ]] && pass "$(t "Il sito risponde" "Site responds") ($c)" || fail "$(t "La home risponde" "Home page answers") $c"
FINAL=$(curl -s -o /dev/null -L -A "$UA" --max-time 15 -w "%{url_effective}" "$B/")
B=$(sed -E 's#^(https?://[^/]+).*#\1#' <<<"$FINAL")
HTML=$(get "$B/")
grep -qE 'wp-content|wp-includes|/wp-json' <<<"$HTML" || hint "$(t "Non sembra WordPress: alcuni controlli potrebbero non avere senso" "Does not look like WordPress: some checks may not apply")"

echo "== HTTPS"
# Si seguono tutti i redirect (es. http://sito → http://www.sito → https://www.sito): conta dove si arriva.
r=$(curl -s -o /dev/null -L -A "$UA" --max-time 15 -w "%{url_effective}" "http://$S/")
[[ "$r" == https://* ]] && pass "$(t "http reindirizza a https" "http redirects to https")" || fail "$(t "http non reindirizza a https" "http does not redirect to https") ($r)"
if command -v openssl >/dev/null; then
	end=$(echo | openssl s_client -servername "$S" -connect "$S:443" 2>/dev/null | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
	exp=""; [[ -n "$end" ]] && exp=$(date -d "$end" +%s 2>/dev/null)
	if [[ -n "$exp" ]]; then
		days=$(( (exp - $(date +%s)) / 86400 ))
		(( days > 14 )) && pass "$(t "Certificato valido ancora $days giorni" "Certificate valid for $days more days")" || hint "$(t "Il certificato scade tra $days giorni" "Certificate expires in $days days")"
	fi
fi

echo "== $(t "Intestazioni di sicurezza (consigliate)" "Security headers (recommended)")"
H=$(curl -sI -L -A "$UA" --max-time 15 "$B/" | tr -d '\r')
for h in strict-transport-security x-content-type-options x-frame-options referrer-policy permissions-policy content-security-policy; do
	grep -qi "^$h:" <<<"$H" && pass "$h" || hint "$(t "manca" "missing") $h"
done
v=$(grep -i '^x-powered-by:' <<<"$H" | head -1)
[[ -n "$v" ]] && hint "$(t "X-Powered-By mostra il software" "X-Powered-By shows the software"): ${v#*: }" || pass "$(t "X-Powered-By nascosto" "X-Powered-By hidden")"
v=$(grep -i '^server:' <<<"$H" | head -1)
[[ "$v" =~ [0-9] ]] && hint "$(t "Server mostra la versione" "Server shows its version"): ${v#*: }" || pass "$(t "Server senza versione" "Server without version")"

echo "== $(t "File che non devono essere scaricabili" "Files that must not be downloadable")"
for f in wp-config.php wp-config.php.bak wp-config.php~ wp-config-sample.php .htaccess .htpasswd .env .git/config error_log wp-content/debug.log debug.log; do
	c=$(code "$B/$f")
	if [[ "$c" == 200 ]]; then
		body=$(curl -s -A "$UA" --max-time 15 "$B/$f" | head -c 2000)
		# An executed wp-config.php returns an empty page: no data leaks.
		if [[ "$f" == wp-config.php && -z "${body//[[:space:]]/}" ]]; then
			pass "/$f $(t "eseguito, non leggibile (200 vuoto)" "executed, not readable (empty 200)")"
		else
			fail "/$f $(t "scaricabile" "downloadable") (200)"
		fi
	else
		pass "/$f ($c)"
	fi
done
for f in readme.html license.txt; do
	c=$(code "$B/$f")
	[[ "$c" == 200 ]] && hint "/$f $(t "accessibile: rivela che è WordPress" "reachable: reveals it is WordPress")" || pass "/$f ($c)"
done

echo "== $(t "Elenco dei file nelle cartelle" "Directory listing")"
for d in wp-content/ wp-content/uploads/ wp-content/plugins/ wp-content/themes/ wp-includes/; do
	grep -qi "<title>Index of" <<<"$(curl -s -A "$UA" --max-time 15 "$B/$d")" && fail "/$d $(t "mostra l'elenco dei file" "lists its files")" || pass "/$d"
done

echo "== $(t "Accesso e XML-RPC" "Login and XML-RPC")"
if [[ -n "$LOGIN" ]]; then
	r=$(curl -s -o /dev/null -L -A "$UA" --max-time 15 -w "%{http_code} %{url_effective}" "$B$LOGIN")
	[[ "${r%% *}" == 200 ]] && pass "$(t "Login personalizzato" "Custom login") $HIDDEN $(t "raggiungibile" "reachable")" || hint "Login $HIDDEN → ${r%% *}"
	c=$(code "$B/wp-login.php")
	[[ "$c" =~ ^(403|404)$ ]] && pass "/wp-login.php $(t "nascosto" "hidden") ($c)" || fail "/wp-login.php $(t "risponde" "answers") $c $(t "anche con il login personalizzato" "despite the custom login")"
	r=$(curl -s -o /dev/null -L -A "$UA" --max-time 15 -w "%{http_code} %{url_effective}" "$B/wp-admin/")
	[[ "$r" == *"$LOGIN"* ]] && fail "/wp-admin/ $(t "porta al login personalizzato" "leads to the custom login")" || pass "/wp-admin/ $(t "non rivela il login" "does not reveal the login") (${r%% *})"
else
	c=$(code "$B/wp-login.php")
	[[ "$c" == 200 ]] && hint "/wp-login.php $(t "all'indirizzo standard: va bene con password forte e 2FA" "at the standard address: fine with a strong password and 2FA")" || pass "/wp-login.php ($c)"
fi
x=$(curl -s -A "$UA" --max-time 15 -H "Content-Type: text/xml" --data '<?xml version="1.0"?><methodCall><methodName>system.listMethods</methodName></methodCall>' "$B/xmlrpc.php")
if grep -q "<methodResponse>" <<<"$x"; then
	grep -q "pingback.ping" <<<"$x" && fail "$(t "XML-RPC attivo, con pingback" "XML-RPC enabled, with pingback")" || hint "$(t "XML-RPC attivo" "XML-RPC enabled")"
else
	pass "$(t "XML-RPC disattivato o bloccato" "XML-RPC disabled or blocked")"
fi

echo "== $(t "Nomi utente" "Usernames")"
for u in "/wp-json/wp/v2/users" "/?rest_route=/wp/v2/users"; do
	s=$(get "$B$u" | grep -o '"slug":"[^"]*"' | cut -d'"' -f4 | head -5 | tr '\n' ' ')
	[[ -n "$s" ]] && fail "API $u $(t "elenca gli utenti" "lists users"): $s" || pass "API $u $(t "non elenca utenti" "lists no users")"
done
c=$(code "$B/?author=1"); l=$(loc "$B/?author=1")
[[ "$l" == */author/* ]] && fail "?author=1 $(t "rivela il nome" "reveals the name"): ${l%/}" || pass "?author=1 $(t "non rivela il nome" "does not reveal the name") ($c)"
a=$(get "$B/wp-json/oembed/1.0/embed?url=$B/" | grep -o '"author_url":"[^"]*"' | cut -d'"' -f4 | sed 's#\\/#/#g')
[[ -n "$a" ]] && hint "$(t "oEmbed mostra la pagina autore" "oEmbed shows the author page"): $a ($(t "nome pubblico: controlla che non sia quello di accesso" "public name: make sure it is not the login name"))"

echo "== $(t "Versione di WordPress" "WordPress version")"
g=$(grep -oiE '<meta name="generator" content="WordPress [^"]*"' <<<"$HTML" | head -1)
[[ -n "$g" ]] && hint "$(t "La home mostra la versione" "Home page shows the version"): ${g#*content=}" || pass "$(t "Nessuna versione nel codice della home" "No version in the home page code")"
f=$(get "$B/feed/" | grep -o '<generator>[^<]*' | head -1)
[[ "$f" == *"?v="* ]] && hint "$(t "Il feed mostra la versione" "Feed shows the version"): ${f#<generator>}" || pass "$(t "Nessuna versione nel feed" "No version in the feed")"

# WordPress mette la sua versione nei ?ver= dei file di wp-includes (temi e plugin usano le loro).
wv=$(grep -oE 'wp-includes/[^"'"'"' ]+\?ver=[0-9]+\.[0-9][0-9.a-z-]*' <<<"$HTML" | grep -oE 'ver=[0-9][0-9.a-z-]*' | sort | uniq -c | sort -rn | head -1 | awk '{print $2}')
[[ -n "$wv" ]] && hint "$(t "Versione nei file di wp-includes" "Version in wp-includes files"): ${wv#ver=}" || pass "$(t "Nessuna versione nei file di wp-includes" "No version in wp-includes files")"

echo "== Plugin"
# I plugin si vedono dai percorsi nella home; il loro readme.txt di solito dice la versione installata.
plugins=$(grep -oE 'wp-content/plugins/[a-zA-Z0-9_-]+/' <<<"$HTML" | cut -d/ -f3 | sort -u)
if [[ -z "$plugins" ]]; then
	pass "$(t "Nessun plugin visibile nel codice della home" "No plugins visible in the home page code")"
else
	open=()
	for p in $plugins; do
		r=$(curl -s -A "$UA" --max-time 15 "$B/wp-content/plugins/$p/readme.txt" | head -c 3000)
		grep -qiE '^(=== |stable tag:)' <<<"$r" && open+=("$p")
	done
	n=$(wc -w <<<"$plugins" | tr -d ' ')
	if (( ${#open[@]} )); then
		hint "$(t "readme.txt leggibile (rivela la versione)" "readme.txt readable (reveals the version)"): ${open[*]}"
	else
		pass "$(t "$n plugin visibili, nessun readme.txt leggibile" "$n plugins visible, no readable readme.txt"): $(tr '\n' ' ' <<<"$plugins")"
	fi
fi

echo
printf '%s: %s%d ok%s · %s%d %s%s · %s%d %s%s\n' "$(t "Risultato" "Result")" "$G" "$ok" "$N" "$R" "$ko" "$(t "problemi" "problems")" "$N" "$Y" "$warn" "$(t "consigli" "tips")" "$N"
echo "✗ = $(t "da sistemare" "to fix")   ! = $(t "consigliato, dipende dal sito" "recommended, depends on the site")"
[[ $ko -eq 0 ]]
