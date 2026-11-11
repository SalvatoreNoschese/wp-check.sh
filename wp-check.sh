#!/usr/bin/env bash
# wp-check.sh — quick outside-in security check of a WordPress site.
# Usage:  bash wp-check.sh [--it|--en] [--no-update] [site]      e.g. bash wp-check.sh --en example.com
# Read-only requests, like any visitor: no login attempts, no attacks. Use it on your own sites.
# Salvatore Noschese — https://github.com/SalvatoreNoschese/wp-check.sh — GPLv3

WPC_VER="1.1"
UPDATE_URL="https://raw.githubusercontent.com/SalvatoreNoschese/wp-check.sh/main/wp-check.sh"
UA="Mozilla/5.0 (X11; Linux x86_64; rv:140.0) Gecko/20100101 Firefox/140.0"
ok=0; ko=0; warn=0

# --- Welcome ---
echo "Welcome to wp-check $WPC_VER"
echo

# --- Language ---
LNG=""; S=""; NOUP=0
for a in "$@"; do
	case "$a" in
		--it) LNG=it ;;
		--en) LNG=en ;;
		--no-update) NOUP=1 ;;
		*) S="$a" ;;
	esac
done
if [[ -z "$LNG" ]]; then
	printf 'Please select language\n  1) English\n  2) Italiano\n'
	read -r -p "[1]: " n; [[ "$n" == 2 ]] && LNG=it || LNG=en
	echo
fi
[[ "$LNG" == it ]] || LNG=en
t() { [[ "$LNG" == it ]] && printf '%s' "$1" || printf '%s' "$2"; }   # usage: t "italian" "english"
pl() { (( $1 == 1 )) && printf '%s' "$2" || printf '%s' "$3"; }   # usage: pl N "singular" "plural"
echo "$(t "Controllo della sicurezza di WordPress, visto da fuori: solo richieste in lettura, come un visitatore qualsiasi." "Outside-in WordPress security check: read-only requests, like any visitor.")"
echo

if [[ -t 1 ]]; then G=$'\033[32m'; R=$'\033[31m'; Y=$'\033[33m'; D=$'\033[2m'; N=$'\033[0m'; else G=; R=; Y=; D=; N=; fi
pass() { printf '  %s✓%s %s\n' "$G" "$N" "$1"; ok=$((ok+1)); }
fail() { printf '  %s✗%s %s\n' "$R" "$N" "$1"; ko=$((ko+1)); }
hint() { printf '  %s!%s %s\n' "$Y" "$N" "$1"; warn=$((warn+1)); }
# mark, then how "advice": the advice is printed once, only if a ✗ or ! came up since the mark.
mark() { n0=$((ko+warn)); }
how()  { (( ko + warn > n0 )) && printf '    %s→ %s%s\n' "$D" "$1" "$N"; return 0; }
code() { curl -s -o /dev/null -A "$UA" --max-time 15 -w "%{http_code}" "$@"; }
loc()  { curl -s -o /dev/null -A "$UA" --max-time 15 -w "%{redirect_url}" "$@"; }
get()  { curl -s -L -A "$UA" --max-time 15 "$@"; }
TMP=$(mktemp) || exit 2; trap 'rm -f "$TMP"' EXIT
# probe URL: follows redirects, saves the page in $TMP, prints "code final-url".
probe() { curl -s -L -A "$UA" --max-time 15 -o "$TMP" -w "%{http_code} %{url_effective}" "$1"; }
has_form() { grep -q 'name="log"' "$TMP" && grep -q 'name="pwd"' "$TMP"; }
mask() { [[ -n "$LOGIN" ]] && printf '%s' "${1//$LOGIN/$HIDDEN}" || printf '%s' "$1"; }

# --- Requirements ---
missing=()
for cmd in curl grep sed cut tr head date sort uniq awk wc mktemp od; do
	command -v "$cmd" >/dev/null || missing+=("$cmd")
done
if (( ${#missing[@]} )); then
	echo "$(t "Mancano" "Missing"): ${missing[*]}"
	echo "Termux: pkg install ${missing[*]/date/coreutils}   ·   Debian/Ubuntu: sudo apt install ${missing[*]/date/coreutils}"
	exit 2
fi
command -v openssl >/dev/null || echo "($(t "openssl non c'è: salto la scadenza del certificato" "openssl not found: certificate expiry skipped") — pkg install openssl-tool)"

# The script can update itself (or delete itself at the end) only when it runs from a writable .sh file,
# not when piped, e.g. bash <(curl ...).
SELF=0; [[ -f "$0" && -w "$0" && "$0" == *.sh ]] && SELF=1

# --- Update check ---
# True when version $1 is newer than $2 (numeric, dot by dot: 1.10 > 1.9). A local copy newer than
# the one on GitHub is never "updated" backwards.
ver_gt() {
	awk -v a="$1" -v b="$2" 'BEGIN { n = split(a, x, "."); m = split(b, y, "."); if (m > n) n = m
		for (i = 1; i <= n; i++) { if (x[i] + 0 > y[i] + 0) exit 0; if (x[i] + 0 < y[i] + 0) exit 1 }; exit 1 }'
}
# Reads WPC_VER from the script on GitHub (3 s at most, silent on network errors). Interactive: offers to
# update and restarts with the same options. From cron: one line, so the mailed result mentions it.
check_update() {
	(( NOUP )) && return
	local rv new
	rv=$(curl -fsSL --max-time 3 "$UPDATE_URL" 2>/dev/null | grep -m1 '^WPC_VER=' | cut -d'"' -f2)
	[[ "$rv" =~ ^[0-9]+(\.[0-9]+)*$ ]] && ver_gt "$rv" "$WPC_VER" || return
	echo "${Y}$(t "Nuova versione disponibile" "New version available"): $rv ($(t "questa è la" "this is") $WPC_VER)${N}"
	if [[ ! -t 0 || ! -t 1 ]] || (( ! SELF )); then
		echo "  curl -fsSLO $UPDATE_URL"; echo; return
	fi
	read -r -p "$(t "Aggiorno ora? [S/n]" "Update now? [Y/n]") " ans || { echo; return; }
	if [[ "$ans" =~ ^[nN] ]]; then echo; return; fi
	# Download next to the script, check it is complete and valid bash, then swap it in one move
	# (a new file, not an overwrite: the running bash keeps reading the old one).
	new=$(mktemp "$0.XXXXXX") || return
	if curl -fsSL --max-time 30 "$UPDATE_URL" -o "$new" && grep -q "^WPC_VER=\"$rv\"" "$new" && bash -n "$new" 2>/dev/null; then
		[[ -x "$0" ]] && chmod +x "$new"
		if mv -f -- "$new" "$0"; then
			echo "$(t "Aggiornato alla" "Updated to") $rv"; echo
			rm -f "$TMP"
			args=(--"$LNG" --no-update); [[ -n "$S" ]] && args+=("$S")
			exec bash "$0" "${args[@]}"
		fi
	fi
	rm -f "$new"
	echo "$(t "Aggiornamento non riuscito: continuo con la" "Update failed: going on with") $WPC_VER"; echo
}
check_update

# One full check of a site; returns 0 when there are no problems.
check_site() {
	ok=0; ko=0; warn=0
	# --- Site ---
	[[ -z "$S" ]] && { read -r -p "$(t "Sito da controllare (es. esempio.it)" "Site to check (e.g. example.com)"): " S; echo; }
	S="${S#http://}"; S="${S#https://}"; S="${S%%/*}"
	[[ -z "$S" ]] && { t "Nessun sito indicato." "No site given."; echo; return 2; }
	LOGIN=""; HIDDEN="/•••"; SKIP=0; SKIPPED=""

	B="https://$S"
	echo "== $B"

	# 1. Does it answer?
	c=$(code "$B/")
	if [[ "$c" == 000 ]]; then
		echo "  $(t "Nessuna risposta da $B: verifica l'indirizzo o la tua connessione." "No answer from $B: check the address or your connection.")"
		return 2
	fi
	[[ "$c" =~ ^(200|301|302)$ ]] && pass "$(t "Il sito risponde" "Site responds") ($c)" || fail "$(t "La home risponde" "Home page answers") $c"
	FINAL=$(curl -s -o /dev/null -L -A "$UA" --max-time 15 -w "%{url_effective}" "$B/")
	B=$(sed -E 's#^(https?://[^/]+).*#\1#' <<<"$FINAL")
	HTML=$(get "$B/")

	# 2. Is it WordPress? admin-ajax.php answers 400 with the body "0": typical of WordPress, and it cannot
	# be hidden without breaking plugins. (admin-post.php answers an empty 200, like many pages: alone it proves nothing.)
	# Fallback when admin-ajax is blocked: WordPress paths in the home page HTML.
	ajax=$(curl -s -A "$UA" --max-time 15 -w ' %{http_code}' "$B/wp-admin/admin-ajax.php")
	if [[ "$ajax" != "0 400" ]] && ! grep -qE 'wp-content|wp-includes|/wp-json' <<<"$HTML"; then
		echo "  $(t "Non riesco a trovare WordPress a questo indirizzo. Ciao!" "I can't find WordPress at this address. Bye!")"
		return 2
	fi
	pass "$(t "WordPress trovato" "WordPress found")"

	# 3. Where is the login? First try on our own: wp-login.php and the variants that often slip through.
	# Every answer showing the login form is either: standard (exactly /wp-login.php), "revealed" (a redirect
	# leads to another address: the custom login found without knowing it) or "bypassed" (the form shows up
	# on an address that should be blocked, e.g. /wp-login.php/x or /wp-admin/x).
	OLD=(wp-login.php wp-login.php/x "wp-login.php?action=lostpassword" "wp-login.php?action=register" wp-admin/ wp-admin/index.php wp-admin/index.php/x wp-admin/x wp-admin/options.php login admin dashboard)
	RES=(); FORM=()   # same index as OLD (plain arrays: works with macOS bash 3 too)
	STD=0; AUTO=""
	for i in "${!OLD[@]}"; do
		u="${OLD[$i]}"; r=$(probe "$B/$u"); RES[$i]="$r"; FORM[$i]=0
		has_form || continue
		FORM[$i]=1
		fp="${r#* }"; fp="${fp#"$B"}"; fp="${fp%%\?*}"; fp="${fp%/}"
		[[ "$u" == wp-login.php && "$fp" == /wp-login.php ]] && { STD=1; break; }
		# Redirect to a different address, neither wp-login.php nor wp-admin: that is the custom login.
		if [[ -z "$AUTO" && "$fp" != "/${u%%\?*}" && "$fp" != /wp-login.php* && "$fp" != /wp-admin* ]]; then LOGIN="$fp"; AUTO="/$u"; fi
	done

	# 4. wp-login.php does not show the login: it was moved, and its address is needed to check it.
	# Never shown, neither while typing (not even its length) nor in the results. Verified at once.
	# When nobody can answer (cron, closed input) the login checks are skipped.
	if (( ! STD )) && [[ -z "$AUTO" ]]; then
		echo
		echo "  $(t "wp-login.php non mostra il form di accesso: il login è stato spostato a un indirizzo personalizzato." "wp-login.php does not show the login form: the login has been moved to a custom address.")"
		echo "  $(t "Per controllare che sia davvero nascosto serve quell'indirizzo (non viene mostrato, né ora né nei risultati)." "To check it is really hidden, that address is needed (it is not shown, neither now nor in the results).")"
		while :; do
			read -r -s -p "  $(t "Indirizzo di login" "Login address"): " LOGIN || { echo; SKIP=1; LOGIN=""; break; }
			LOGIN="${LOGIN// /}"; LOGIN="${LOGIN#"$B"}"; LOGIN="${LOGIN#"$S"}"; LOGIN="${LOGIN%/}"
			if [[ -n "$LOGIN" ]]; then
				[[ "$LOGIN" != /* ]] && LOGIN="/$LOGIN"
				r=$(probe "$B$LOGIN")
				if [[ "${r%% *}" == 200 ]] && has_form; then echo; pass "$(t "Login personalizzato" "Custom login") $HIDDEN $(t "trovato, con il form di accesso" "found, with the login form")"; break; fi
				echo " ✗"
				echo "  $(t "Nessun form di accesso a quell'indirizzo" "No login form at that address") (${r%% *}): $(t "forse un errore di battitura?" "maybe a typo?")"
			else
				echo
				echo "  $(t "Nessun indirizzo inserito." "No address entered.")"
			fi
			LOGIN=""
			read -r -p "  $(t "[R]iprova o [S]alta i controlli sul login?" "[R]etry or [S]kip the login checks?") " ans || { SKIP=1; break; }
			[[ "$ans" =~ ^[sS] ]] && { SKIP=1; break; }
		done
	fi

	echo; echo "== HTTPS"
	# Follow every redirect (e.g. http://site → http://www.site → https://www.site): where it ends is what counts.
	mark
	r=$(curl -s -o /dev/null -L -A "$UA" --max-time 15 -w "%{url_effective}" "http://$S/")
	[[ "$r" == https://* ]] && pass "$(t "http reindirizza a https" "http redirects to https")" || fail "$(t "http non reindirizza a https" "http does not redirect to https") ($r)"
	how "$(t "Reindirizza tutto http verso https (pannello dell'hosting, .htaccess o configurazione del server)." "Redirect all http traffic to https (hosting panel, .htaccess or server config).")"
	if command -v openssl >/dev/null; then
		# The certificate of the host the site ends on (e.g. www.site), not the one typed.
		CH="${B#*://}"; CH="${CH%%:*}"
		cert=$(echo | openssl s_client -servername "$CH" -connect "$CH:443" 2>/dev/null | openssl x509 2>/dev/null)
		if [[ -n "$cert" ]]; then
			mark
			end=$(openssl x509 -noout -enddate <<<"$cert" | cut -d= -f2)
			# GNU date (Linux, Termux), then BSD date (macOS).
			exp=$(date -d "$end" +%s 2>/dev/null || date -j -f "%b %d %T %Y %Z" "$end" +%s 2>/dev/null)
			if [[ -n "$exp" ]]; then
				days=$(( (exp - $(date +%s)) / 86400 ))
				(( days > 14 )) && pass "$(t "Certificato valido ancora $days $(pl $days giorno giorni)" "Certificate valid for $days more $(pl $days day days)")" || hint "$(t "Il certificato scade tra $days $(pl $days giorno giorni)" "Certificate expires in $days $(pl $days day days)")"
			else
				# Date not readable: openssl can still tell whether it expires within 14 days.
				openssl x509 -noout -checkend $((14*86400)) <<<"$cert" >/dev/null && pass "$(t "Certificato valido per più di 14 giorni" "Certificate valid for more than 14 days")" || hint "$(t "Il certificato scade entro 14 giorni" "Certificate expires within 14 days")"
			fi
			how "$(t "Controlla che il rinnovo automatico del certificato funzioni." "Make sure automatic certificate renewal works.")"
		fi
	fi

	echo; echo "== $(t "Intestazioni di sicurezza (consigliate)" "Security headers (recommended)")"
	H=$(curl -sI -L -A "$UA" --max-time 15 "$B/" | tr -d '\r')
	mark
	for h in strict-transport-security x-content-type-options x-frame-options referrer-policy permissions-policy content-security-policy; do
		grep -qi "^$h:" <<<"$H" && pass "$h" || hint "$(t "manca" "missing") $h"
	done
	how "$(t "Aggiungili nella configurazione del server (.htaccess, nginx) o con un plugin; CSP va provata con cura." "Add them in the server config (.htaccess, nginx) or with a plugin; test CSP carefully.")"
	mark
	v=$(grep -i '^x-powered-by:' <<<"$H" | head -1)
	[[ -n "$v" ]] && hint "$(t "X-Powered-By mostra il software" "X-Powered-By shows the software"): ${v#*: }" || pass "$(t "X-Powered-By nascosto" "X-Powered-By hidden")"
	v=$(grep -i '^server:' <<<"$H" | head -1)
	[[ "$v" =~ [0-9] ]] && hint "$(t "Server mostra la versione" "Server shows its version"): ${v#*: }" || pass "$(t "Server senza versione" "Server without version")"
	how "$(t "Nascondi le versioni nel server (es. ServerTokens Prod, server_tokens off, expose_php = Off)." "Hide versions in the server (e.g. ServerTokens Prod, server_tokens off, expose_php = Off).")"

	echo; echo "== $(t "File che non devono essere scaricabili" "Files that must not be downloadable")"
	mark
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
	how "$(t "Elimina questi file dal sito o bloccane l'accesso (.htaccess, nginx): possono contenere password." "Delete these files from the site or deny access (.htaccess, nginx): they may contain passwords.")"
	mark
	for f in readme.html license.txt; do
		c=$(code "$B/$f")
		[[ "$c" == 200 ]] && hint "/$f $(t "accessibile: rivela che è WordPress" "reachable: reveals it is WordPress")" || pass "/$f ($c)"
	done
	how "$(t "Blocca l'accesso con il server: se li elimini, tornano a ogni aggiornamento." "Deny access in the server: deleted, they come back with every update.")"

	echo; echo "== $(t "Elenco dei file nelle cartelle" "Directory listing")"
	mark
	for d in wp-content/ wp-content/uploads/ wp-content/plugins/ wp-content/themes/ wp-includes/; do
		grep -qi "<title>Index of" <<<"$(curl -s -A "$UA" --max-time 15 "$B/$d")" && fail "/$d $(t "mostra l'elenco dei file" "lists its files")" || pass "/$d"
	done
	how "$(t "Disattiva l'elenco: Options -Indexes in .htaccess (Apache) o autoindex off (nginx)." "Turn listing off: Options -Indexes in .htaccess (Apache) or autoindex off (nginx).")"

	echo; echo "== $(t "Accesso e XML-RPC" "Login and XML-RPC")"
	(( STD )) && hint "/wp-login.php $(t "all'indirizzo standard: va bene con password forte e 2FA" "at the standard address: fine with a strong password and 2FA")"
	mark   # the standard login is fine as it is: no advice for it
	if (( STD )); then :
	elif (( SKIP )); then
		# Without the address, still report any login form found where it should not be.
		for i in "${!RES[@]}"; do (( FORM[i] )) && fail "/${OLD[$i]} $(t "mostra il login" "shows the login") (${RES[$i]})"; done
		SKIPPED="$(t "controlli sul login nascosto (indirizzo non indicato)" "hidden login checks (address not given)")"
	else
		if [[ -n "$LOGIN" ]]; then
			# A typed address was already confirmed above; only the case where it turned up by itself is left.
			[[ -n "$AUTO" ]] && fail "$(t "Login personalizzato trovato senza conoscerlo: $AUTO porta a" "Custom login found without knowing it: $AUTO leads to") $HIDDEN"
		fi
		# Old addresses and variants: any answer is fine (403, 404, redirect…) as long as it does not show
		# the login form and does not lead to the custom login.
		bad=0
		for i in "${!RES[@]}"; do
			u="${OLD[$i]}"; r="${RES[$i]}"
			if (( FORM[i] )) || [[ -n "$LOGIN" && "${r#* }" == *"$LOGIN"* ]]; then
				fail "/$u $(t "mostra il login" "shows the login") ($(mask "${r%% *} ${r#* }"))"; bad=$((bad+1))
			fi
		done
		lbad=$bad
		# Links to the login in the site: in the HTML (home and 404 page, which carry the theme header and footer)
		# and following internal links like a crawler would. One hidden link in the theme is enough to reveal it.
		P404="/$(od -An -N6 -tx1 /dev/urandom | tr -d ' \n')-x/"
		if [[ -n "$LOGIN" ]]; then
			# Only links to THIS site: https://site/path, //site/path, https:\/\/site\/path (JSON)
			# or relative href="/path". Not the same word anywhere, nor google.com/path.
			q() { printf '%s' "$1" | sed 's/[.[\*^$()+?{}|]/\\&/g'; }
			RX="((https?:)?(\\\\?/){2}$(q "${B#*://}")\\\\?/|[\"'(=]/)$(q "${LOGIN#/}")([/?#\"'<> &\\\\]|$)"
			leak=""
			for u in / "$P404" /feed/; do get "$B$u" | grep -Eqi "$RX" && leak+=" ${u/$P404/404}"; done
			[[ -n "$leak" ]] && { fail "$(t "Link al login personalizzato nel codice di" "Link to the custom login in the code of"):$leak"; lbad=$((lbad+1)); }
		fi
		links=$( { get "$B/"; get "$B$P404"; } | grep -oiE 'href=["'"'"'][^"'"'"'#]+' | sed -E 's/^href=.//' \
			| sed -E "s#^//#https://#; s#^/#$B/#" | grep -iE "^${B//./\\.}(/|$)" \
			| grep -viE '\.(css|js|png|jpe?g|gif|webp|avif|svg|ico|woff2?|ttf|xml|zip|gz|pdf|mp4|webm)(\?|$)' | sort -u | head -150)
		# Every opened page: it must not be the login form and, when the path is known, must not link to it
		# (a hidden link can sit in any post, not only in the theme).
		n=0; bad=0; inpg=()
		while IFS= read -r l; do
			[[ -z "$l" ]] && continue; n=$((n+1)); probe "$l" >/dev/null
			if has_form; then fail "$(t "Questo link porta al login" "This link leads to the login"): $(mask "${l#$B}")"; bad=$((bad+1))
			elif [[ -n "$LOGIN" ]] && grep -Eqi "$RX" "$TMP"; then pg="${l#$B}"; inpg+=("$(mask "${pg:-/}")"); fi
		done <<<"$links"
		(( ${#inpg[@]} )) && { fail "$(t "Link al login personalizzato in" "Link to the custom login in") ${#inpg[@]} $(t "$(pl ${#inpg[@]} pagina pagine)" "$(pl ${#inpg[@]} page pages)"): ${inpg[*]:0:5}"; bad=$((bad+1)); }
		lbad=$((lbad+bad))
		(( lbad )) || pass "$(t "Login nascosto: wp-login.php, $((${#OLD[@]}-1)) varianti note e $n $(pl $n "pagina interna" "pagine interne"), nessuno lo rivela" "Hidden login: wp-login.php, $((${#OLD[@]}-1)) known variants and $n internal $(pl $n page pages), none reveals it")"
	fi
	how "$(t "Blocca questi indirizzi (403 o 404) nel plugin che nasconde il login o nel server, e togli il link da tema, menu o articoli." "Block these addresses (403 or 404) in the hide-login plugin or the server, and remove the link from theme, menus or posts.")"
	mark
	x=$(curl -s -A "$UA" --max-time 15 -H "Content-Type: text/xml" --data '<?xml version="1.0"?><methodCall><methodName>system.listMethods</methodName></methodCall>' "$B/xmlrpc.php")
	if grep -q "<methodResponse>" <<<"$x"; then
		grep -q "pingback.ping" <<<"$x" && fail "$(t "XML-RPC attivo, con pingback" "XML-RPC enabled, with pingback")" || hint "$(t "XML-RPC attivo" "XML-RPC enabled")"
	else
		pass "$(t "XML-RPC disattivato o bloccato" "XML-RPC disabled or blocked")"
	fi
	how "$(t "Se non usi app o Jetpack, blocca /xmlrpc.php (server o plugin di sicurezza)." "If you use no apps or Jetpack, block /xmlrpc.php (server or security plugin).")"

	echo; echo "== $(t "Nomi utente" "Usernames")"
	mark
	for u in "/wp-json/wp/v2/users" "/?rest_route=/wp/v2/users"; do
		s=$(get "$B$u" | grep -o '"slug":"[^"]*"' | cut -d'"' -f4 | head -5 | tr '\n' ' ')
		[[ -n "$s" ]] && fail "API $u $(t "elenca gli utenti" "lists users"): $s" || pass "API $u $(t "non elenca utenti" "lists no users")"
	done
	c=$(code "$B/?author=1"); l=$(loc "$B/?author=1")
	[[ "$l" == */author/* ]] && fail "?author=1 $(t "rivela il nome" "reveals the name"): ${l%/}" || pass "?author=1 $(t "non rivela il nome" "does not reveal the name") ($c)"
	how "$(t "Limita l'API degli utenti a chi ha fatto l'accesso e reindirizza ?author= alla home (plugin di sicurezza o poche righe di codice)." "Restrict the users API to logged-in users and redirect ?author= to the home page (security plugin or a few lines of code).")"
	a=$(get "$B/wp-json/oembed/1.0/embed?url=$B/" | grep -o '"author_url":"[^"]*"' | cut -d'"' -f4 | sed 's#\\/#/#g')
	[[ -n "$a" ]] && hint "$(t "oEmbed mostra la pagina autore" "oEmbed shows the author page"): $a ($(t "nome pubblico: controlla che non sia quello di accesso" "public name: make sure it is not the login name"))"

	echo; echo "== $(t "Versione di WordPress" "WordPress version")"
	mark
	g=$(grep -oiE '<meta name="generator" content="WordPress [^"]*"' <<<"$HTML" | head -1)
	[[ -n "$g" ]] && hint "$(t "La home mostra la versione" "Home page shows the version"): ${g#*content=}" || pass "$(t "Nessuna versione nel codice della home" "No version in the home page code")"
	f=$(get "$B/feed/" | grep -o '<generator>[^<]*' | head -1)
	[[ "$f" == *"?v="* ]] && hint "$(t "Il feed mostra la versione" "Feed shows the version"): ${f#<generator>}" || pass "$(t "Nessuna versione nel feed" "No version in the feed")"

	# WordPress puts its own version in the ?ver= of wp-includes files (themes and plugins use their own).
	wv=$(grep -oE 'wp-includes/[^"'"'"' ]+\?ver=[0-9]+\.[0-9][0-9.a-z-]*' <<<"$HTML" | grep -oE 'ver=[0-9][0-9.a-z-]*' | sort | uniq -c | sort -rn | head -1 | awk '{print $2}')
	[[ -n "$wv" ]] && hint "$(t "Versione nei file di wp-includes" "Version in wp-includes files"): ${wv#ver=}" || pass "$(t "Nessuna versione nei file di wp-includes" "No version in wp-includes files")"
	how "$(t "Togli la versione da generator, feed e ?ver= (plugin di sicurezza o ottimizzazione). Soprattutto: tieni WordPress aggiornato." "Remove the version from generator, feed and ?ver= (security or optimization plugin). Above all: keep WordPress updated.")"

	echo; echo "== Plugin"
	# Plugins show up from the paths in the home page; their readme.txt usually states the installed version.
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
			how "$(t "Blocca l'accesso ai readme.txt in /wp-content/plugins/ con il server, e tieni i plugin aggiornati." "Deny access to readme.txt in /wp-content/plugins/ in the server, and keep plugins updated.")"
		else
			pass "$(t "$n plugin $(pl $n rilevato rilevati) nel codice della home, nessun readme.txt leggibile" "$n $(pl $n plugin plugins) found in the home page code, no readable readme.txt"): $(tr '\n' ' ' <<<"$plugins")"
		fi
	fi

	echo
	cr=$G; (( ko )) && cr=$R; cy=$G; (( warn )) && cy=$Y
	printf '%s: %s%d ok%s · %s%d %s%s · %s%d %s%s\n' "$(t "Risultato" "Result")" "$G" "$ok" "$N" "$cr" "$ko" "$(t "problemi" "problems")" "$N" "$cy" "$warn" "$(t "consigli" "tips")" "$N"
	echo "✗ = $(t "da sistemare" "to fix")   ! = $(t "consigliato, dipende dal sito" "recommended, depends on the site")"
	[[ -n "$SKIPPED" ]] && echo "$(t "Saltati" "Skipped"): $SKIPPED"
	[[ $ko -eq 0 ]]
}

# At the end: another site, quit, or delete the script. Terminal only (from cron it exits with the code).
while :; do
	check_site; rc=$?
	[[ -t 0 && -t 1 ]] || exit $rc
	echo
	echo "$(t "Cosa vuoi fare?" "What next?")"
	echo "  1) $(t "Esci (predefinito)" "Quit (default)")"
	echo "  2) $(t "Controlla un altro sito" "Check another site")"
	(( SELF )) && echo "  3) $(t "Elimina questo script ed esci" "Delete this script and quit")"
	read -r -p "[1]: " n || exit $rc
	case "$n" in
		2) S=""; echo ;;
		3) (( SELF )) && rm -f -- "$0" && echo "$(t "Script eliminato" "Script deleted"): $0"; exit $rc ;;
		*) exit $rc ;;
	esac
done
