#!/usr/bin/env bash
# wp-check.sh — quick outside-in security check of a WordPress site.
# Usage:  bash wp-check.sh [--it|--en] [--no-update] [site]      e.g. bash wp-check.sh --en example.com
# Read-only requests, like any visitor: no login attempts, no attacks (except one optional, confirmed
# CAPTCHA test with a made-up user). Use it on your own sites.
# Salvatore Noschese — https://github.com/SalvatoreNoschese/wp-check.sh — GPLv3

WPC_VER="1.5"
UPDATE_URL="https://raw.githubusercontent.com/SalvatoreNoschese/wp-check.sh/main/wp-check.sh"
UA="Mozilla/5.0 (X11; Linux x86_64; rv:140.0) Gecko/20100101 Firefox/140.0"
ok=0; ko=0; warn=0; unv=0

# --- Welcome ---
echo "Welcome to wp-check $WPC_VER"
echo

# --- Language ---
LNG=""; S=""; NOUP=0
usage() { echo "Usage: bash wp-check.sh [--it|--en] [--no-update] [site]" >&2; exit 2; }
for a in "$@"; do
	case "$a" in
		--it|--IT) LNG=it ;;
		--en|--EN) LNG=en ;;
		--no-update) NOUP=1 ;;
		-h|--help) echo "Usage: bash wp-check.sh [--it|--en] [--no-update] [site]"; exit 0 ;;
		-*) usage ;;   # an unknown option is an error, not a site name
		*) [[ -z "$S" ]] || usage; S="$a" ;;
	esac
done
# Asked only with a terminal: from cron or a pipe nobody can answer, English is used.
if [[ -z "$LNG" && -t 0 ]]; then
	printf 'Please select language\n  1) English\n  2) Italiano\n'
	read -r -p "[1]: " n || n=""
	if [[ "$n" == 2 ]]; then LNG=it; else LNG=en; fi
	echo
fi
[[ "$LNG" == it ]] || LNG=en
t() { [[ "$LNG" == it ]] && printf '%s' "$1" || printf '%s' "$2"; }   # usage: t "italian" "english"
pl() { (( $1 == 1 )) && printf '%s' "$2" || printf '%s' "$3"; }   # usage: pl N "singular" "plural"
t "Controllo della sicurezza di WordPress, visto da fuori: solo richieste in lettura, come un visitatore qualsiasi." "Outside-in WordPress security check: read-only requests, like any visitor."
echo; echo

# Colors and the self-erasing status line only on a real terminal that can show them: not in cron mail or a
# pipe, not with TERM=dumb. NO_COLOR (https://no-color.org) turns colors off but keeps the status line.
# Only the 8 basic colors, bold and dim: the terminal theme (light or dark) decides the actual shades.
TTY=0; [[ -t 1 && "${TERM:-dumb}" != dumb ]] && TTY=1
if (( TTY )) && [[ -z "${NO_COLOR:-}" ]]; then G=$'\033[32m'; R=$'\033[31m'; Y=$'\033[33m'; D=$'\033[2m'; BD=$'\033[1m'; N=$'\033[0m'; else G=; R=; Y=; D=; BD=; N=; fi
# Progress on one line that is then wiped (terminal only): long waits do not look like a hang.
# Kept short (under 40 columns): \r only goes back to the start of the last screen line.
prog() { (( TTY )) && printf '\r\033[K  %s%s%s' "$D" "$1" "$N"; return 0; }
clr()  { (( TTY )) && printf '\r\033[K'; return 0; }
# sec "Title": a section heading, bold so it stands out when scrolling a long result.
sec()  { clr; printf '\n%s==%s %s%s%s\n' "$D" "$N" "$BD" "$1" "$N"; }
pass() { clr; printf '  %s✓%s %s\n' "$G" "$N" "$1"; ok=$((ok+1)); }
fail() { clr; printf '  %s✗%s %s\n' "$R" "$N" "$1"; ko=$((ko+1)); FAILS+=("$1"); }
hint() { clr; printf '  %s!%s %s\n' "$Y" "$N" "$1"; warn=$((warn+1)); }
# A plain piece of information: neither ok nor a problem, not counted.
info() { clr; printf '  %s→ %s%s\n' "$D" "$1" "$N"; }
# Not verifiable: a bot shield answered instead of the site. Neither ok nor a problem, and no advice.
unk()  { clr; printf '  %s?%s %s\n' "$D" "$N" "$1 — $(t "non verificabile: ha risposto $SHN, non il sito" "not verifiable: $SHN answered, not the site")"; unv=$((unv+1)); }
# mark, then how "advice": the advice is printed once, only if a ✗ or ! came up since the mark.
mark() { n0=$((ko+warn)); }
how()  { (( ko + warn > n0 )) && printf '    %s→ %s%s\n' "$D" "$1" "$N"; return 0; }
# code: status only; body and headers are kept in $TMPB/$TMPH, so shield can tell who answered.
code() { curl -s -o "$TMPB" -D "$TMPH" -A "$UA" --max-time 15 -w "%{http_code}" "$@"; }
loc()  { curl -s -o /dev/null -A "$UA" --max-time 15 -w "%{redirect_url}" "$@"; }
get()  { curl -s -L -A "$UA" --max-time 15 "$@"; }
TMP=$(mktemp) && TMPB=$(mktemp) && TMPH=$(mktemp) || exit 2; trap 'rm -f "$TMP" "$TMPB" "$TMPH"' EXIT
# probe URL: follows redirects, saves the page in $TMP (headers in $TMPH), prints "code final-url".
probe() { curl -s -L -A "$UA" --max-time 15 -o "$TMP" -D "$TMPH" -w "%{http_code} %{url_effective}" "$1"; }
# A bot shield answering instead of the site: a JavaScript challenge or a block page (of the host, a CDN or a
# firewall plugin). A script cannot pass it, so whatever comes from it (a 403 included) says nothing about the site.
# Only signs of a block or a challenge count, never the mere presence of the service: Cloudflare, Sucuri or
# Imunify360 also sit in front of sites that answer normally, and a login with Turnstile loads challenges.cloudflare.com.
# One line per shield: "Name|regex on the body". Then the header signs, same format.
SHB=(
	'Cloudflare|<title>Just a moment|cf-error-details|Attention Required! \| Cloudflare|Sorry, you have been blocked'
	'Imunify360|Imunify360 bot-protection|imunify360-webshield|Access denied by Imunify360'
	'SiteGround|sgcaptcha'
	'Sucuri|Sucuri WebSite Firewall|sucuri\.net/privacy-policy'
	'Imperva|Incapsula incident ID|_Incapsula_Resource'
	'Akamai|errors\.edgesuite\.net|Reference&#32;&#35;'
	'AWS WAF|AwsWafIntegration|awswaf-|Generated by cloudfront'
	'DDoS-Guard|<title>DDoS-Guard|ddos-guard\.net/'
	'Vercel|Vercel Security Checkpoint'
	'Anubis|Making sure you.re not a bot|id="anubis_'
	'Wordfence|Generated by Wordfence|Your access to this site has been limited by the site owner'
)
SHH=(
	'Cloudflare|^cf-mitigated:'
	'SiteGround|^location:.*sgcaptcha'
	'Vercel|^x-vercel-mitigated:'
	'Sucuri|^x-sucuri-block:'
)
# shield_txt "body" [headers]: true when a shield answered; its name goes in $SHN (and once in $SHSEEN).
shield_txt() {
	local e
	for e in "${SHH[@]}"; do grep -qiE "${e#*|}" <<<"$2" && { shield_hit "${e%%|*}"; return 0; }; done
	for e in "${SHB[@]}"; do grep -qiE "${e#*|}" <<<"$1" && { shield_hit "${e%%|*}"; return 0; }; done
	return 1
}
shield_hit() { SHN="$1"; [[ " $SHSEEN " == *" $1 "* ]] || SHSEEN="${SHSEEN:+$SHSEEN, }$1"; }
# shield FILE: the body in FILE, the headers of the last code or probe in $TMPH.
shield() { shield_txt "$(head -c 20000 "$1" 2>/dev/null)" "$(cat "$TMPH" 2>/dev/null)"; }
has_form() { grep -q 'name="log"' "$TMP" && grep -q 'name="pwd"' "$TMP"; }
# is_html TEXT: true when TEXT is a web page (first non-empty line opens an HTML document).
is_html() { grep -m1 -v '^[[:space:]]*$' <<<"$1" | grep -qiE '^[[:space:]]*(.{0,3})<(!doctype html|html[[:space:]>])'; }
# wp_file NAME: true when the body in $TMPB is WordPress's own readme.html or license.txt, not another page.
wp_file() {
	case "$1" in
		readme.html) grep -qiE 'WordPress &#8250; ReadMe|wordpress-logo\.png|Semantic Personal Publishing' "$TMPB" ;;
		*) ! is_html "$(head -c 2000 "$TMPB")" ;;
	esac
}
# is_admin NAME...: true when one of the names is "admin" or "administrator".
is_admin() { local x; for x in "$@"; do [[ "$x" == admin || "$x" == administrator ]] && return 0; done; return 1; }
# is_admin_list TEXT: the same, for a list with one name per line.
is_admin_list() { grep -qxE 'admin|administrator' <<<"$1"; }
# mname NAME: a username masked (ad•••, a••• when very short): seen, not handed out in a screenshot.
# "admin" stays in clear: it is the default every bot already tries, and it is reported by name anyway.
mname() { if is_admin "$1"; then printf '%s' "$1"; elif (( ${#1} <= 3 )); then printf '%s•••' "${1:0:1}"; else printf '%s•••' "${1:0:2}"; fi; }
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
			rm -f "$TMP" "$TMPB" "$TMPH"
			args=(--"$LNG" --no-update); [[ -n "$S" ]] && args+=("$S")
			exec bash "$0" "${args[@]}"
		fi
	fi
	rm -f "$new"
	echo "$(t "Aggiornamento non riuscito: continuo con la" "Update failed: going on with") $WPC_VER"; echo
}
check_update

skipped() { SKIPPED+="${SKIPPED:+; }$1"; }

# Does the CAPTCHA really block? The only check that is not read-only: it sends the login form once, with a
# made-up user, a random password and no CAPTCHA answer. Nobody can log in, but the server logs a failed
# login, so it runs only after a confirmation (default no), never from cron.
captcha_test() {
	local page act user resp code err ans
	if [[ ! -t 0 || ! -t 1 ]]; then skipped "$(t "verifica che il CAPTCHA blocchi (serve una conferma)" "check that the CAPTCHA blocks (needs a confirmation)")"; return; fi
	echo "    $(t "Test facoltativo: il CAPTCHA blocca davvero?" "Optional test: does the CAPTCHA really block?")"
	echo "    $(t "Invia il form una volta, con un utente inventato e senza CAPTCHA." "It sends the form once, with a made-up user and no CAPTCHA.")"
	echo "    $(t "Nessuno entra, ma il server registra un accesso fallito: solo sul tuo sito." "Nobody gets in, but the server logs a failed login: your own site only.")"
	read -r -p "    $(t "Eseguo il test del CAPTCHA? [s/N]" "Run the CAPTCHA test? [y/N]") " ans || ans=""
	if [[ ! "$ans" =~ ^[sSyY] ]]; then skipped "$(t "verifica che il CAPTCHA blocchi (non confermata)" "check that the CAPTCHA blocks (not confirmed)")"; return; fi
	prog "$(t "Invio il form di prova" "Sending the test form")…"
	# Post where the form posts, as a browser would (the action may differ from the page address).
	page=$(get "$1")
	act=$(grep -oiE '<form[^>]*id="loginform"[^>]*>' <<<"$page" | grep -oiE 'action="[^"]+"' | head -1 | cut -d'"' -f2 | sed 's/&amp;/\&/g; s/&#038;/\&/g')
	[[ "$act" == /* ]] && act="$BH$act"; [[ "$act" == http* ]] || act="$1"
	user="wpcheck_$(od -An -N5 -tx1 /dev/urandom | tr -d ' \n')"
	resp=$(curl -sL --post301 --post302 -A "$UA" --max-time 15 -b "wordpress_test_cookie=WP%20Cookie%20check" \
		--data "log=$user&pwd=$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')&wp-submit=Log+In&testcookie=1" \
		-w $'\n%{http_code}' "$act")
	code="${resp##*$'\n'}"; resp="${resp%$'\n'*}"
	# Only the error box counts: the page shown again may prefill the user field even when the CAPTCHA blocked.
	err=""; [[ "$resp" == *'id="login_error"'* ]] && { err="${resp#*id=\"login_error\"}"; err="${err%%</div>*}"; }
	if [[ -n "$err" && "$err" == *"$user"* ]]; then
		fail "$(t "Il CAPTCHA non blocca: il form arriva a WordPress senza risposta CAPTCHA" "The CAPTCHA does not block: the form reaches WordPress without a CAPTCHA answer")"
		how "$(t "Controlla che il plugin CAPTCHA protegga anche questo indirizzo di login (opzione per login personalizzati) o provane un altro. Alcuni plugin verificano solo per utenti esistenti: in quel caso è un falso allarme." "Make sure the CAPTCHA plugin also protects this login address (option for custom logins) or try another one. Some plugins only check for existing users: then this is a false alarm.")"
	elif grep -qiE 'captcha|robot|anti-?bot|altcha|turnstile|verifica|verification|challenge' <<<"${err:-$resp}" || [[ "$code" =~ ^(403|429)$ ]]; then
		pass "$(t "Il CAPTCHA blocca davvero: form fermato senza risposta CAPTCHA" "The CAPTCHA really blocks: form stopped without a CAPTCHA answer") ($code)"
	else
		hint "$(t "Risposta non chiara al form senza CAPTCHA" "Unclear answer to the form without CAPTCHA") ($code): $(t "prova a mano, vedi il README" "test by hand, see the README")"
	fi
}

# One full check of a site; returns 0 when there are no problems.
check_site() {
	ok=0; ko=0; warn=0; unv=0; LSHIELD=0; SHN=""; SHSEEN=""; FAILS=()
	# --- Site ---
	[[ -z "$S" ]] && { read -r -p "$(t "Sito da controllare (es. esempio.it)" "Site to check (e.g. example.com)"): " S; echo; }
	# Host in $S, subfolder (WordPress installed in /blog, say) in $P: "" for the root.
	S="${S#http://}"; S="${S#https://}"; S="${S%%[?#]*}"
	P=""; [[ "$S" == */* ]] && P="/${S#*/}"; S="${S%%/*}"
	while [[ "$P" == */ ]]; do P="${P%/}"; done
	[[ -z "$S" ]] && { t "Nessun sito indicato." "No site given."; echo; return 2; }
	LOGIN=""; HIDDEN="/•••"; SKIP=0; SKIPPED=""

	B="https://$S$P"
	printf '%s==%s %s%s%s\n' "$D" "$N" "$BD" "$B" "$N"

	# 1. Does it answer?
	prog "$(t "Contatto il sito" "Contacting the site")…"
	c=$(code "$B/")
	if [[ "$c" == 000 ]]; then
		clr; echo "  $(t "Nessuna risposta da $B: verifica l'indirizzo o la tua connessione." "No answer from $B: check the address or your connection.")"
		return 2
	fi
	# The whole site behind a bot check: nothing below would be about the site.
	if [[ ! "$c" =~ ^(200|301|302)$ ]] && shield "$TMPB"; then
		clr; echo "  $(t "Il sito risponde con la verifica anti-bot di $SHN al posto delle pagine: da uno script non si può controllare." "The site answers with the $SHN bot check instead of its pages: it cannot be checked from a script.")"
		return 2
	fi
	if [[ "$c" =~ ^(200|301|302)$ ]]; then pass "$(t "Il sito risponde" "Site responds") ($c)"; else fail "$(t "La home risponde" "Home page answers") $c"; fi
	prog "$(t "Leggo la home" "Reading the home page")…"
	FINAL=$(curl -s -o /dev/null -L -A "$UA" --max-time 15 -w "%{url_effective}" "$B/")
	# The host the site ends on (e.g. www.), with the subfolder given: $BH is the host alone, for root-relative links.
	BH=$(sed -E 's#^(https?://[^/]+).*#\1#' <<<"$FINAL"); B="$BH$P"
	HTML=$(get "$B/")
	# A page cache may serve a copy made long ago. The same home with a random parameter usually skips it:
	# that one shows the site as it is now, while $HTML is what visitors (and bots) actually get.
	FRESH=$(get "$B/?wpc=$(od -An -N4 -tx1 /dev/urandom | tr -d ' \n')")
	[[ -n "$FRESH" ]] || FRESH="$HTML"

	# 2. Is it WordPress? admin-ajax.php answers 400 with the body "0": typical of WordPress, and it cannot
	# be hidden without breaking plugins. (admin-post.php answers an empty 200, like many pages: alone it proves nothing.)
	# Fallback when admin-ajax is blocked: WordPress paths in the home page HTML.
	ajax=$(curl -s -A "$UA" --max-time 15 -w ' %{http_code}' "$B/wp-admin/admin-ajax.php")
	if [[ "$ajax" != "0 400" ]] && ! grep -qE 'wp-content|wp-includes|/wp-json' <<<"$HTML"; then
		clr; echo "  $(t "Non riesco a trovare WordPress a questo indirizzo. Ciao!" "I can't find WordPress at this address. Bye!")"
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
		prog "$(t "Cerco il form di accesso" "Looking for the login form")… $((i+1))/${#OLD[@]}"
		u="${OLD[$i]}"; r=$(probe "$B/$u"); RES[i]="$r"; FORM[i]=0
		# wp-login.php behind a bot check: no form to see, which does not mean the login was moved.
		[[ "$u" == wp-login.php ]] && ! has_form && shield "$TMP" && { LSHIELD=1; LSHN="$SHN"; break; }
		has_form || continue
		FORM[i]=1
		fp="${r#* }"; fp="${fp#"$B"}"; fp="${fp%%\?*}"; fp="${fp%/}"
		[[ "$u" == wp-login.php && "$fp" == /wp-login.php ]] && { STD=1; break; }
		# Redirect to a different address, neither wp-login.php nor wp-admin: that is the custom login.
		if [[ -z "$AUTO" && "$fp" != "/${u%%\?*}" && "$fp" != /wp-login.php* && "$fp" != /wp-admin* ]]; then LOGIN="$fp"; AUTO="/$u"; fi
	done
	clr

	# 4. wp-login.php does not show the login: it was moved, and its address is needed to check it.
	# Never shown, neither while typing (not even its length) nor in the results. Verified at once.
	# When nobody can answer (cron, closed input) the login checks are skipped.
	if (( LSHIELD )); then
		echo
		echo "  $(t "wp-login.php è dietro la verifica anti-bot di $SHN: uno script non vede il form, quindi il login non si può controllare." "wp-login.php is behind the $SHN bot check: a script cannot see the form, so the login cannot be checked.")"
		SKIP=1
	elif (( ! STD )) && [[ -z "$AUTO" ]]; then
		echo
		echo "  $(t "wp-login.php non mostra il form di accesso: il login è stato spostato a un indirizzo personalizzato." "wp-login.php does not show the login form: the login has been moved to a custom address.")"
		echo "  $(t "Per controllare che sia davvero nascosto serve quell'indirizzo (mai mostrato)." "To check it is really hidden, that address is needed (never shown).")"
		while :; do
			read -r -s -p "  $(t "Indirizzo di login" "Login address"): " LOGIN || { echo; SKIP=1; LOGIN=""; break; }
			LOGIN="${LOGIN// /}"; LOGIN="${LOGIN#"$B"}"; LOGIN="${LOGIN#"$S$P"}"; LOGIN="${LOGIN#"$S"}"; LOGIN="${LOGIN%/}"
				# Typed with the subfolder (/blog/secret): keep the part after it, the subfolder is already in $B.
				[[ -n "$P" && "$LOGIN" == "$P"/* ]] && LOGIN="${LOGIN#"$P"}"
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
			read -r -p "  $(t "Riprovo o salto i controlli sul login? [R/s]" "Retry or skip the login checks? [R/s]") " ans || { SKIP=1; break; }
			[[ "$ans" =~ ^[sS] ]] && { SKIP=1; break; }
		done
	fi

	sec HTTPS
	# Follow every redirect (e.g. http://site → http://www.site → https://www.site): where it ends is what counts.
	mark
	r=$(curl -s -o /dev/null -L -A "$UA" --max-time 15 -w "%{url_effective}" "http://$S$P/")
	if [[ "$r" == https://* ]]; then pass "$(t "http reindirizza a https" "http redirects to https")"; else fail "$(t "http non reindirizza a https" "http does not redirect to https") ($r)"; fi
	how "$(t "Reindirizza tutto http verso https (pannello dell'hosting, .htaccess o configurazione del server)." "Redirect all http traffic to https (hosting panel, .htaccess or server config).")"
	if command -v openssl >/dev/null; then
		# The certificate of the host the site ends on (e.g. www.site), not the one typed.
		CH="${BH#*://}"; CH="${CH%%:*}"
		prog "$(t "Leggo il certificato" "Reading the certificate")…"
		# openssl has no timeout of its own: "timeout" (coreutils) where available, so a silent port cannot hang the check.
		TO=(); command -v timeout >/dev/null && TO=(timeout 15)
		cert=$(echo | "${TO[@]}" openssl s_client -servername "$CH" -connect "$CH:443" 2>/dev/null | openssl x509 2>/dev/null)
		if [[ -n "$cert" ]]; then
			mark
			end=$(openssl x509 -noout -enddate <<<"$cert" | cut -d= -f2)
			# GNU date (Linux, Termux), then BSD date (macOS).
			exp=$(date -d "$end" +%s 2>/dev/null || date -j -f "%b %d %T %Y %Z" "$end" +%s 2>/dev/null)
			if [[ -n "$exp" ]]; then
				days=$(( (exp - $(date +%s)) / 86400 ))
				if (( days > 14 )); then pass "$(t "Certificato valido ancora $days $(pl "$days" giorno giorni)" "Certificate valid for $days more $(pl "$days" day days)")"
				else hint "$(t "Il certificato scade tra $days $(pl "$days" giorno giorni)" "Certificate expires in $days $(pl "$days" day days)")"; fi
			else
				# Date not readable: openssl can still tell whether it expires within 14 days.
				if openssl x509 -noout -checkend $((14*86400)) <<<"$cert" >/dev/null; then pass "$(t "Certificato valido per più di 14 giorni" "Certificate valid for more than 14 days")"
				else hint "$(t "Il certificato scade entro 14 giorni" "Certificate expires within 14 days")"; fi
			fi
			how "$(t "Controlla che il rinnovo automatico del certificato funzioni." "Make sure automatic certificate renewal works.")"
		fi
	fi

	sec "$(t "Intestazioni di sicurezza (consigliate)" "Security headers (recommended)")"
	prog "$(t "Leggo le intestazioni" "Reading the headers")…"
	H=$(curl -sI -L -A "$UA" --max-time 15 "$B/" | tr -d '\r')
	mark
	for h in strict-transport-security x-content-type-options x-frame-options referrer-policy permissions-policy content-security-policy; do
		if grep -qi "^$h:" <<<"$H"; then pass "$h"; else hint "$(t "manca" "missing") $h"; fi
	done
	hh=$((ko + warn - n0)); mark   # header advice is printed at the end of the section
	v=$(grep -i '^x-powered-by:' <<<"$H" | head -1)
	if [[ -n "$v" ]]; then hint "$(t "X-Powered-By mostra il software" "X-Powered-By shows the software"): ${v#*: }"; else pass "$(t "X-Powered-By nascosto" "X-Powered-By hidden")"; fi
	v=$(grep -i '^server:' <<<"$H" | head -1)
	if [[ "$v" =~ [0-9] ]]; then hint "$(t "Server mostra la versione" "Server shows its version"): ${v#*: }"; else pass "$(t "Server senza versione" "Server without version")"; fi
	hv=$((ko + warn - n0)); n0=-1   # n0=-1: the advice below is printed by the flags, not by the counters
	(( hh )) && how "$(t "Aggiungi le intestazioni mancanti nella configurazione del server (.htaccess, nginx) o con un plugin; CSP va provata con cura." "Add the missing headers in the server config (.htaccess, nginx) or with a plugin; test CSP carefully.")"
	(( hv )) && how "$(t "Nascondi le versioni nel server (es. ServerTokens Prod, server_tokens off, expose_php = Off)." "Hide versions in the server (e.g. ServerTokens Prod, server_tokens off, expose_php = Off).")"

	sec "$(t "File che non devono essere scaricabili" "Files that must not be downloadable")"
	mark
	for f in wp-config.php wp-config.php.bak wp-config.php~ wp-config-sample.php .htaccess .htpasswd .env .git/config error_log wp-content/debug.log debug.log; do
		prog "$(t "Controllo" "Checking") $f…"
		c=$(code "$B/$f")
		if [[ "$c" != 200 ]] && shield "$TMPB"; then
			unk "/$f ($c)"
		elif [[ "$c" == 200 ]]; then
			body=$(head -c 2000 "$TMPB")
			# An executed wp-config.php returns an empty page: no data leaks.
			if [[ "$f" == wp-config.php && -z "${body//[[:space:]]/}" ]]; then
				pass "/$f $(t "eseguito, non leggibile (200 vuoto)" "executed, not readable (empty 200)")"
			# Some sites answer 200 with a page (home, theme "not found") for files that do not exist: a web
			# page is not the file. None of these files is HTML, so an HTML answer cannot be a leak.
			elif is_html "$body"; then
				pass "/$f (200: $(t "una pagina del sito, non il file" "a site page, not the file"))"
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
		prog "$(t "Controllo" "Checking") $f…"
		c=$(code "$B/$f")
		if [[ "$c" != 200 ]] && shield "$TMPB"; then unk "/$f ($c)"
		elif [[ "$c" == 200 ]] && ! wp_file "$f"; then pass "/$f (200: $(t "una pagina del sito, non il file" "a site page, not the file"))"
		elif [[ "$c" == 200 ]]; then hint "/$f $(t "accessibile: rivela che è WordPress" "reachable: reveals it is WordPress")"
		else pass "/$f ($c)"; fi
	done
	how "$(t "Blocca l'accesso con il server: se li elimini, tornano a ogni aggiornamento." "Deny access in the server: deleted, they come back with every update.")"

	sec "$(t "Elenco dei file nelle cartelle" "Directory listing")"
	mark
	for d in wp-content/ wp-content/uploads/ wp-content/plugins/ wp-content/themes/ wp-includes/; do
		prog "$(t "Controllo" "Checking") $d…"
		c=$(code "$B/$d")
		if [[ "$c" != 200 ]] && shield "$TMPB"; then unk "/$d ($c)"
		elif grep -qi "<title>Index of" "$TMPB"; then fail "/$d $(t "mostra l'elenco dei file" "lists its files")"
		else pass "/$d"; fi
	done
	how "$(t "Disattiva l'elenco: Options -Indexes in .htaccess (Apache) o autoindex off (nginx)." "Turn listing off: Options -Indexes in .htaccess (Apache) or autoindex off (nginx).")"

	sec "$(t "Accesso e XML-RPC" "Login and XML-RPC")"
	(( STD )) && hint "/wp-login.php $(t "all'indirizzo standard: va bene con password forte e 2FA" "at the standard address: fine with a strong password and 2FA")"
	mark   # the standard login is fine as it is: no advice for it
	if (( STD )); then :
	elif (( LSHIELD )); then
		SHN="$LSHN"; unk "/wp-login.php"
		skipped "$(t "controlli sul login (dietro la verifica anti-bot)" "login checks (behind the bot check)")"
	elif (( SKIP )); then
		# Without the address, still report any login form found where it should not be.
		for i in "${!RES[@]}"; do (( FORM[i] )) && fail "/${OLD[$i]} $(t "mostra il login" "shows the login") (${RES[$i]})"; done
		skipped "$(t "controlli sul login nascosto (indirizzo non indicato)" "hidden login checks (address not given)")"
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
			# shellcheck disable=SC2016  # a sed expression, not shell variables
			q() { printf '%s' "$1" | sed 's/[.[\*^$()+?{}|]/\\&/g'; }
			# Host and subfolder, with every / also matching \/ (JSON).
			HP=$(q "${B#*://}" | sed 's#/#\\\\?/#g')
			RX="((https?:)?(\\\\?/){2}$HP\\\\?/|[\"'(=]$(q "$P")/)$(q "${LOGIN#/}")([/?#\"'<> &\\\\]|$)"
			leak=""
			prog "$(t "Cerco link al login" "Looking for login links")…"
			for u in / "$P404" /feed/; do get "$B$u" | grep -Eqi "$RX" && leak+=" ${u/$P404/404}"; done
			[[ -n "$leak" ]] && { fail "$(t "Link al login personalizzato nel codice di" "Link to the custom login in the code of"):$leak"; lbad=$((lbad+1)); }
		fi
		links=$( { get "$B/"; get "$B$P404"; } | grep -oiE 'href=["'"'"'][^"'"'"'#]+' | sed -E 's/^href=.//' \
			| sed -E "s#^//#https://#; s#^/#$BH/#" | grep -iE "^${B//./\\.}(/|$)" \
			| grep -viE '\.(css|js|png|jpe?g|gif|webp|avif|svg|ico|woff2?|ttf|xml|zip|gz|pdf|mp4|webm)(\?|$)' | sort -u | head -150)
		# Every opened page: it must not be the login form and, when the path is known, must not link to it
		# (a hidden link can sit in any post, not only in the theme).
		n=0; bad=0; inpg=(); tot=$(grep -c . <<<"$links")
		while IFS= read -r l; do
			[[ -z "$l" ]] && continue; n=$((n+1))
			prog "$(t "Seguo i link interni" "Following internal links")… $n/$tot"; probe "$l" >/dev/null
			if has_form; then fail "$(t "Questo link porta al login" "This link leads to the login"): $(mask "${l#"$B"}")"; bad=$((bad+1))
			elif [[ -n "$LOGIN" ]] && grep -Eqi "$RX" "$TMP"; then pg="${l#"$B"}"; inpg+=("$(mask "${pg:-/}")"); fi
		done <<<"$links"
		clr
		(( ${#inpg[@]} )) && { fail "$(t "Link al login personalizzato in" "Link to the custom login in") ${#inpg[@]} $(t "$(pl "${#inpg[@]}" pagina pagine)" "$(pl "${#inpg[@]}" page pages)"): ${inpg[*]:0:5}"; bad=$((bad+1)); }
		lbad=$((lbad+bad))
		(( lbad )) || pass "$(t "Login nascosto: wp-login.php, $((${#OLD[@]}-1)) varianti note e $n $(pl "$n" "pagina interna" "pagine interne"), nessuno lo rivela" "Hidden login: wp-login.php, $((${#OLD[@]}-1)) known variants and $n internal $(pl "$n" page pages), none reveals it")"
	fi
	how "$(t "Blocca questi indirizzi (403 o 404) nel plugin che nasconde il login o nel server, e togli il link da tema, menu o articoli." "Block these addresses (403 or 404) in the hide-login plugin or the server, and remove the link from theme, menus or posts.")"
	mark
	prog "$(t "Provo XML-RPC" "Trying XML-RPC")…"
	x=$(curl -s -A "$UA" --max-time 15 -H "Content-Type: text/xml" --data '<?xml version="1.0"?><methodCall><methodName>system.listMethods</methodName></methodCall>' "$B/xmlrpc.php")
	if shield_txt "$x"; then
		unk "XML-RPC"
	elif grep -q "<methodResponse>" <<<"$x"; then
		if grep -q "pingback.ping" <<<"$x"; then fail "$(t "XML-RPC attivo, con pingback" "XML-RPC enabled, with pingback")"; else hint "$(t "XML-RPC attivo" "XML-RPC enabled")"; fi
	else
		pass "$(t "XML-RPC disattivato o bloccato" "XML-RPC disabled or blocked")"
	fi
	how "$(t "Se non usi app o Jetpack, blocca /xmlrpc.php (server o plugin di sicurezza)." "If you use no apps or Jetpack, block /xmlrpc.php (server or security plugin).")"

	# CAPTCHA on the login form actually used (standard or custom): read-only, the page is only looked at.
	# It shows the widget is there, not that it is verified: the README has a manual test for that.
	NOCAP=0; LURL=""
	(( STD )) && LURL="$B/wp-login.php"; (( ! STD )) && [[ -n "$LOGIN" ]] && LURL="$B$LOGIN"
	if [[ -n "$LURL" ]]; then
		mark
		prog "$(t "Leggo il form di accesso" "Reading the login form")…"
		cap=$(get "$LURL" | grep -oiE 'altcha|recaptcha|h-?captcha|turnstile|frc-captcha|friendly-?captcha|captcha' | head -1 | tr '[:upper:]' '[:lower:]')
		case "$cap" in h-captcha) cap=hcaptcha ;; frc-captcha|friendly-captcha) cap=friendlycaptcha ;; esac
		if [[ -n "$cap" ]]; then
			pass "$(t "CAPTCHA nel form di accesso" "CAPTCHA on the login form") ($cap)"
		else
			NOCAP=1
			hint "$(t "Nessun CAPTCHA nel form di accesso: va bene con password forte, 2FA o un limite ai tentativi" "No CAPTCHA on the login form: fine with a strong password, 2FA or a limit on attempts")"
		fi
		how "$(t "Aggiungi un CAPTCHA (es. ALTCHA, Turnstile) e verifica che protegga proprio l'indirizzo di login che usi." "Add a CAPTCHA (e.g. ALTCHA, Turnstile) and make sure it protects the login address actually in use.")"
		[[ -n "$cap" ]] && { mark; captcha_test "$LURL"; }
	fi

	sec "$(t "Nomi utente" "Usernames")"
	mark
	# Usernames are public, but half of a login: they are shown masked (ad•••), so a screenshot does not hand
	# them out. The site owner sees them all at the address of the API. "admin" is reported apart: masked,
	# it would hide the worst case.
	ADM=0; APIOPEN=""
	# The first 3 by ID (ID 1 is almost always the account made at install, the main admin) and the total
	# from X-WP-Total, so a site with 1000 users is one line. Roles are not visible without logging in.
	# If the site rejects the parameters, the plain request is tried.
	prog "$(t "Leggo l'API degli utenti" "Reading the users API")…"
	for u in "/wp-json/wp/v2/users" "/?rest_route=/wp/v2/users"; do
		[[ "$u" == *\?* ]] && qs="&" || qs="?"
		p=$(curl -s -L -A "$UA" --max-time 15 -D "$TMPH" "$B$u${qs}orderby=id&order=asc&per_page=5")
		grep -q '"slug":"' <<<"$p" || p=$(curl -s -L -A "$UA" --max-time 15 -D "$TMPH" "$B$u")
		shield_txt "$p" "$(cat "$TMPH" 2>/dev/null)" && { unk "API $u"; continue; }
		s=$(grep -o '"slug":"[^"]*"' <<<"$p" | cut -d'"' -f4)
		if [[ -z "$s" ]]; then pass "API $u $(t "non elenca utenti" "lists no users")"; continue; fi
		APIOPEN="$u$qs"; is_admin_list "$s" && ADM=1
		ns=$(head -3 <<<"$s" | grep -c .)
		tot=$(grep -i '^x-wp-total:' "$TMPH" | tail -1 | tr -dc '0-9'); (( ${tot:-0} >= ns )) || tot=$(grep -c . <<<"$s")
		names=""; while IFS= read -r x; do names+="${names:+, }$(mname "$x")"; done < <(head -3 <<<"$s")
		(( tot > ns )) && names+=" (+$((tot - ns)))"
		fail "API $u $(t "elenca $tot $(pl "$tot" utente utenti)" "lists $tot $(pl "$tot" user users)"): $names"
	done
	# ?author=N leads to /author/name/ only for an author with published posts, and WordPress makes the posts
	# of a deleted user go to another one: the author of the latest post is a real author. The posts API gives
	# that ID even when /users is closed. One ID is enough: ?author= is blocked for everyone or for no one.
	# No ID (posts API closed, no posts): skipped, not guessed. A guessed ID that does not exist (ID 1 is often
	# gone, e.g. after replacing "admin") gives a 404 that looks like a block: a false ✓.
	prog "$(t "Provo ?author=" "Trying ?author=")…"
	aid=$(get "$B/wp-json/wp/v2/posts?_fields=author&per_page=1" | grep -o '"author":[0-9]*' | head -1 | cut -d: -f2)
	[[ -n "$aid" ]] || aid=$(get "$B/?rest_route=/wp/v2/posts&_fields=author&per_page=1" | grep -o '"author":[0-9]*' | head -1 | cut -d: -f2)
	if [[ -z "$aid" ]]; then
		clr; skipped "$(t "?author= (nessun ID di autore trovato: API degli articoli chiusa o nessun articolo)" "?author= (no author ID found: posts API closed or no posts)")"
	else
		c=$(code "$B/?author=$aid"); l=$(loc "$B/?author=$aid")
		if [[ "$c" != 200 && "$c" != 30* ]] && shield "$TMPB"; then unk "?author=$aid ($c)"
		elif [[ "$l" == */author/* ]]; then
			x="${l#*/author/}"; x="${x%%/*}"; is_admin "$x" && ADM=1
			fail "?author=$aid $(t "rivela il nome" "reveals the name"): …/author/$(mname "$x")"
		else pass "?author=$aid $(t "(autore dell'ultimo articolo) non rivela il nome" "(author of the latest post) does not reveal the name") ($c)"; fi
	fi
	# oEmbed answers only for a single post or page: the home works only when it is a static page. So the
	# latest post in the feed is asked (the home when the feed has none): nearly every site has one.
	prog "$(t "Chiedo a oEmbed" "Asking oEmbed")…"
	fd=$(get "$B/feed/")
	ol=""; [[ "$fd" == *"<item>"* ]] && ol=$(grep -o '<link>[^<]*' <<<"${fd#*<item>}" | head -1 | cut -c7-)
	if [[ "$ol" == http* ]]; then ow="$(t "dell'ultimo articolo" "of the latest post")"; else ol="$B/"; ow="$(t "della home" "of the home page")"; fi
	oe=$(get "$B/wp-json/oembed/1.0/embed?url=$(sed 's/&amp;/\&/g; s/%/%25/g; s/&/%26/g; s/?/%3F/g; s/#/%23/g' <<<"$ol")")
	a=$(grep -o '"author_url":"[^"]*"' <<<"$oe" | cut -d'"' -f4 | sed 's#\\/#/#g')
	xo=""; [[ "$a" == */author/* ]] && { xo="${a#*/author/}"; xo="${xo%%/*}"; is_admin "$xo" && ADM=1; }
	# Author sitemap: one more side door. robots.txt names the site's sitemaps (WordPress, Yoast, Rank Math,
	# SEOPress… each adds its own; the usual index addresses if it names none); in each index, the child
	# sitemaps of authors or users are opened and the /author/name/ addresses counted. 4-6 requests.
	prog "$(t "Cerco le sitemap degli autori" "Looking for author sitemaps")…"
	sx=$(get "$BH/robots.txt" | tr -d '\r' | grep -i '^sitemap:' | sed -E 's/^[Ss]itemap:[[:space:]]*//' | head -5)
	[[ -n "$sx" ]] || sx=$(printf '%s\n' "$B/sitemap.xml" "$B/sitemap_index.xml" "$B/wp-sitemap.xml")
	asm=""
	while IFS= read -r x; do
		[[ -z "$x" ]] && continue
		if [[ "$x" =~ (author|user)[^/]*\.xml ]]; then asm+="$x"$'\n'; continue; fi
		asm+=$(get "$x" | head -c 300000 | grep -oE '<loc>[^<]*(author|user)[^<]*\.xml[^<]*</loc>' | sed -E 's#</?loc>##g')$'\n'
	done <<<"$sx"
	sml=""; sms=""
	while IFS= read -r x; do
		[[ -z "$x" ]] && continue
		n=$(get "$x" | grep -oE '/author/[^/<"?#]+' | sed 's#^/author/##')
		[[ -n "$n" ]] && { [[ -n "$sml" ]] || sml="/${x#*://*/}"; sms+="$n"$'\n'; }
	done <<<"$(grep . <<<"$asm" | sort -u | head -3)"
	sms=$(grep . <<<"$sms" | sort -u); is_admin_list "$sms" && ADM=1
	if [[ -n "$sms" ]]; then
		tot=$(grep -c . <<<"$sms"); names=""
		while IFS= read -r x; do names+="${names:+, }$(mname "$x")"; done < <(head -3 <<<"$sms")
		(( tot > 3 )) && names+=" (+$((tot - 3)))"
		fail "$(t "La sitemap degli autori" "Author sitemap") $sml $(t "elenca $tot $(pl "$tot" utente utenti)" "lists $tot $(pl "$tot" user users)"): $names"
	else pass "$(t "Nessuna sitemap degli autori" "No author sitemap")"; fi
	# With the API open, a direct question settles whether an "admin" user exists, even beyond the first 3.
	if (( ! ADM )) && [[ -n "$APIOPEN" ]]; then
		for x in admin administrator; do grep -q '"slug":"'"$x"'"' <<<"$(get "$B$APIOPEN"slug=$x)" && { ADM=1; break; }; done
	fi
	(( ADM )) && fail "$(t "C'è un utente \"admin\": è il primo nome che i bot provano" "There is a user named \"admin\": the first name bots try")"
	nc=""; (( NOCAP )) && nc=" $(t "Il login non ha CAPTCHA: un bot può provare password su questi nomi." "The login has no CAPTCHA: a bot can try passwords on these names.")"
	nsm=""; [[ -n "$sms" ]] && nsm=" $(t "Sitemap degli autori: in Yoast o Rank Math si spegne dalle impostazioni, senza plugin SEO con il filtro wp_sitemaps_add_provider." "Author sitemap: in Yoast or Rank Math turn it off in the settings, without an SEO plugin with the wp_sitemaps_add_provider filter.")"
	na=""; (( ADM )) && na=" $(t "Per \"admin\": crea un nuovo amministratore con un altro nome e cancella il vecchio, attribuendo i contenuti al nuovo." "For \"admin\": create a new administrator with another name and delete the old one, giving its content to the new one.")"
	how "$(t "Limita l'API degli utenti a chi ha fatto l'accesso e reindirizza ?author= alla home (plugin di sicurezza o poche righe di codice). I nomi completi li vedi tu all'indirizzo dell'API." "Restrict the users API to logged-in users and redirect ?author= to the home page (security plugin or a few lines of code). You can see the full names at the API address.")$nsm$na$nc"
	# oEmbed last and without advice: the public name of an author is fine, as long as it is not the login.
	if shield_txt "$oe"; then unk "oEmbed"
	elif [[ -n "$xo" ]]; then hint "$(t "oEmbed mostra l'autore $ow" "oEmbed shows the author $ow"): …/author/$(mname "$xo") ($(t "nome pubblico: controlla che non sia quello di accesso" "public name: make sure it is not the login name"))"
	else pass "$(t "oEmbed non mostra l'autore" "oEmbed shows no author")"; fi

	sec "$(t "Versione di WordPress" "WordPress version")"
	mark
	# Every version is read in both pages: the fresh one tells the real version, the cached one what visitors
	# see. When they differ the cached one is labelled, so two versions on screen are not a puzzle.
	gv()  { grep -oiE '<meta name="generator" content="WordPress [0-9][^"]*"' <<<"$1" | head -1 | grep -oE '[0-9][0-9.]*' | head -1; }
	# WordPress puts its own version in the ?ver= of wp-includes files (themes and plugins use their own).
	wiv() { grep -oE 'wp-includes/[^"'"'"' ]+\?ver=[0-9]+\.[0-9][0-9.a-z-]*' <<<"$1" | grep -oE 'ver=[0-9][0-9.a-z-]*' | sort | uniq -c | sort -rn | head -1 | awk '{print $2}' | cut -d= -f2; }
	# vlab FRESH CACHED: the version to show, with the cached one when it differs or is the only one.
	vlab() {
		if [[ -n "$1" && -n "$2" && "$1" != "$2" ]]; then printf '%s (%s: %s)' "$1" "$(t "copia in cache" "cached copy")" "$2"
		elif [[ -n "$1" ]]; then printf '%s' "$1"
		else printf '%s (%s)' "$2" "$(t "copia in cache" "cached copy")"; fi
	}
	g=$(gv "$FRESH"); gc=$(gv "$HTML"); w=$(wiv "$FRESH"); wc=$(wiv "$HTML")
	if [[ -n "$g$gc" ]]; then hint "$(t "La home mostra la versione" "Home page shows the version"): WordPress $(vlab "$g" "$gc")"; else pass "$(t "Nessuna versione nel codice della home" "No version in the home page code")"; fi
	f=$(grep -o '<generator>[^<]*' <<<"$fd" | head -1)
	if shield_txt "$fd"; then unk "$(t "Versione nel feed" "Version in the feed")"
	elif [[ "$f" == *"?v="* ]]; then hint "$(t "Il feed mostra la versione" "Feed shows the version"): ${f#<generator>}"
	else pass "$(t "Nessuna versione nel feed" "No version in the feed")"; fi
	if [[ -n "$w$wc" ]]; then hint "$(t "Versione nei file di wp-includes" "Version in wp-includes files"): $(vlab "$w" "$wc")"; else pass "$(t "Nessuna versione nei file di wp-includes" "No version in wp-includes files")"; fi
	how "$(t "Togli la versione da generator, feed e ?ver= (plugin di sicurezza o ottimizzazione). Soprattutto: tieni WordPress aggiornato." "Remove the version from generator, feed and ?ver= (security or optimization plugin). Above all: keep WordPress updated.")"
	# Two different versions: the page cache serves a home made before the last update.
	rv="${g:-$w}"; cv="${gc:-$wc}"
	if [[ -n "$rv" && -n "$cv" && "$rv" != "$cv" ]]; then
		mark
		hint "$(t "La cache serve una home vecchia: mostra WordPress $cv, il sito è alla $rv" "The page cache serves an old home page: it shows WordPress $cv, the site runs $rv")"
		how "$(t "Svuota la cache delle pagine (plugin di cache, hosting o CDN) e controlla che scada da sola." "Purge the page cache (cache plugin, host or CDN) and make sure it expires on its own.")"
	fi
	# Is that version still safe? WordPress.org lists every release as latest, outdated or insecure
	# (insecure: it has known security issues): the same source WordPress itself uses for updates.
	# Version hidden: only the latest one, as a reminder. API not reachable: skipped, not guessed.
	sv="${rv:-$cv}"
	if [[ -z "$sv" && "$f" == *"?v="* ]]; then sv="${f##*\?v=}"; fi
	prog "$(t "Cerco l'ultima versione" "Checking the latest version")…"
	sc=$(curl -fsS -A "$UA" --max-time 10 "https://api.wordpress.org/core/stable-check/1.0/" 2>/dev/null)
	lat=$(grep -oE '"[0-9][0-9.]*"[[:space:]]*:[[:space:]]*"latest"' <<<"$sc" | head -1 | cut -d'"' -f2)
	if [[ -z "$lat" ]]; then
		clr; skipped "$(t "stato degli aggiornamenti (api.wordpress.org non raggiungibile)" "update status (api.wordpress.org not reachable)")"
	elif [[ -z "$sv" ]]; then
		info "$(t "Ultima versione di WordPress: $lat. Se la tua è più vecchia, aggiorna appena possibile." "Latest WordPress: $lat. If yours is older, update as soon as possible.")"
	else
		mark
		st=$(grep -oE "\"${sv//./\\.}\"[[:space:]]*:[[:space:]]*\"[a-z]+\"" <<<"$sc" | head -1 | cut -d'"' -f4)
		case "$st" in
			latest) pass "$(t "WordPress $sv è l'ultima versione" "WordPress $sv is the latest version")" ;;
			outdated) hint "$(t "WordPress $sv non è l'ultima ($lat): aggiorna appena puoi" "WordPress $sv is not the latest ($lat): update when you can")" ;;
			insecure) fail "$(t "WordPress $sv ha falle di sicurezza note: aggiorna subito (ultima: $lat)" "WordPress $sv has known security issues: update now (latest: $lat)")" ;;
			*) info "$(t "Ultima versione di WordPress: $lat (questa è la $sv)." "Latest WordPress: $lat (this site runs $sv).")" ;;
		esac
		how "$(t "Aggiorna da Bacheca → Aggiornamenti, e lascia attivi gli aggiornamenti automatici di sicurezza." "Update in Dashboard → Updates, and keep automatic security updates on.")"
	fi

	sec Plugin
	# Plugins show up from the paths in the home page; their readme.txt usually states the installed version.
	plugins=$(grep -oE 'wp-content/plugins/[a-zA-Z0-9_-]+/' <<<"$HTML$FRESH" | cut -d/ -f3 | sort -u)
	if [[ -z "$plugins" ]]; then
		pass "$(t "Nessun plugin visibile nel codice della home" "No plugins visible in the home page code")"
	else
		open=(); shp=()
		npt=$(wc -w <<<"$plugins" | tr -d ' '); np=0
		for p in $plugins; do np=$((np+1)); prog "$(t "Leggo i readme" "Reading readmes")… $np/$npt"
			r=$(curl -s -A "$UA" --max-time 15 "$B/wp-content/plugins/$p/readme.txt" | head -c 3000)
			shield_txt "$r" && { shp+=("$p"); continue; }
			grep -qiE '^(=== |stable tag:)' <<<"$r" && open+=("$p")
		done
		(( ${#shp[@]} )) && unk "readme.txt: ${shp[*]}"
		n=$(wc -w <<<"$plugins" | tr -d ' ')
		if (( ${#open[@]} )); then
			hint "$(t "readme.txt leggibile (rivela la versione)" "readme.txt readable (reveals the version)"): ${open[*]}"
			how "$(t "Blocca l'accesso ai readme.txt in /wp-content/plugins/ con il server, e tieni i plugin aggiornati." "Deny access to readme.txt in /wp-content/plugins/ in the server, and keep plugins updated.")"
		else
			pass "$(t "$n plugin $(pl "$n" rilevato rilevati) nel codice della home, nessun readme.txt leggibile" "$n $(pl "$n" plugin plugins) found in the home page code, no readable readme.txt"): $(tr '\n' ' ' <<<"$plugins")"
		fi
	fi

	echo
	cr=$G; (( ko )) && cr=$R; cy=$G; (( warn )) && cy=$Y
	printf '%s: %s%d ok%s · %s%d %s%s · %s%d %s%s' "$(t "Risultato" "Result")" "$G" "$ok" "$N" "$cr" "$ko" "$(t "problemi" "problems")" "$N" "$cy" "$warn" "$(t "consigli" "tips")" "$N"
	(( unv )) && printf ' · %s%d %s%s' "$D" "$unv" "$(t "non verificabili" "not verifiable")" "$N"
	echo
	# The problems again, together: in a long result they are what matters, and they are easy to lose.
	if (( ${#FAILS[@]} )); then
		echo; printf '%s%s:%s\n' "$BD" "$(t "Da sistemare" "To fix")" "$N"
		for x in "${FAILS[@]}"; do printf '  %s✗%s %s\n' "$R" "$N" "$x"; done
		echo
	fi
	echo "✗ = $(t "da sistemare" "to fix")   ! = $(t "consigliato, dipende dal sito" "recommended, depends on the site")"
	(( unv )) && echo "? = $(t "non verificabile: ha risposto la protezione anti-bot ($SHSEEN) al posto del sito. Risultato parziale." "not verifiable: the bot shield ($SHSEEN) answered instead of the site. Partial result.")"
	[[ -n "$SKIPPED" ]] && echo "$(t "Saltati" "Skipped"): $SKIPPED"
	echo
	# With something to fix, where the fixes are: snippets, server rules, a ready mu-plugin.
	(( ko + warn )) && printf '%s→ %s: https://github.com/SalvatoreNoschese/wp-check.sh/blob/main/FIXES.md%s\n' "$D" "$(t "Come sistemare" "How to fix")" "$N"
	printf '%s→ %s: https://tools.salvatorenoschese.it/%s\n' "$D" "$(t "Controlli sul dominio (Whois, DNS)" "Domain checks (Whois, DNS)")" "$N"
	# The version is already in the welcome line. The star is asked only in a terminal, not in cron mail.
	if [[ -t 1 ]]; then st="★ $(t "Ti è utile? Una stella su GitHub" "Useful? Star it on GitHub")"; else st="Salvatore Noschese"; fi
	printf '%s%s: https://github.com/SalvatoreNoschese/wp-check.sh%s\n' "$D" "$st" "$N"
	[[ $ko -eq 0 ]]
}

# At the end: another site, quit, or delete the script. Terminal only (from cron it exits with the code).
while :; do
	check_site; rc=$?
	[[ -t 0 && -t 1 ]] || exit $rc
	echo
	t "Cosa vuoi fare?" "What next?"; echo
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
