<?php
/**
 * Plugin Name: wp-check fixes
 * Description: Fixes for what wp-check.sh reports that WordPress itself can fix: usernames not listable, version hidden, XML-RPC off, security headers on pages.
 * Version:     1.0.0
 * Author:      Salvatore Noschese
 * License:     GPLv3
 *
 * Set the switches below in a text editor, then upload to wp-content/mu-plugins/ (create the folder if missing)
 * by FTP or the hosting file manager, or from the dashboard with MustUse Manager:
 * https://salvatorenoschese.it/mustuse-manager-wordpress-plugin/
 * It runs by itself, no activation.
 * Every block has its switch below: false to turn it off.
 * A syntax error here takes the site down: keep FTP access at hand, and delete the file to undo everything.
 *
 * What a plugin can NOT do (the web server must, see FIXES.md): block readme.html, license.txt, logs and
 * the readme.txt of plugins; turn off directory listing; redirect http to https; put headers on static files.
 */

defined( 'ABSPATH' ) || exit;

const WPCF_USERS   = true; // 1. users API, ?author=N, author in oEmbed, WordPress author sitemap
const WPCF_VERSION = true; // 2. WordPress version out of generator, feed and ?ver= of core files
const WPCF_XMLRPC  = true; // 3. XML-RPC answers 403 (left alone when Jetpack is active)
const WPCF_HEADERS = true; // 4. security headers on pages, X-Powered-By removed

/* ── 1. Usernames ──
 * For visitors who are not logged in: /wp-json/wp/v2/users (and ?rest_route=) lists nobody, ?author=1 is a
 * 404 instead of leading to /author/name/, oEmbed leaves out the author, WordPress's own sitemap has no
 * author list. Logged-in users and the editor work as before. Yoast and Rank Math have their own author
 * sitemap: turn it off in their settings (FIXES.md). Author pages linked from posts stay: their address
 * is the author slug, so it should differ from the login name (one-shot/change-author-slug.php).
 * Hosting panels may have a "block user enumeration" switch too: keep only one of the two (FIXES.md). */
if ( WPCF_USERS ) {
	add_filter( 'rest_endpoints', static function ( $endpoints ) {
		if ( is_user_logged_in() || ! is_array( $endpoints ) ) {
			return $endpoints;
		}
		foreach ( array_keys( $endpoints ) as $route ) {
			if ( 0 === strpos( $route, '/wp/v2/users' ) ) {
				unset( $endpoints[ $route ] );
			}
		}
		return $endpoints;
	} );
	add_filter( 'request', static function ( $vars ) {
		if ( ! is_admin() && isset( $vars['author'] ) && ! isset( $vars['author_name'] ) && ! is_user_logged_in() ) {
			return [ 'error' => '404' ];
		}
		return $vars;
	} );
	add_filter( 'oembed_response_data', static function ( $data ) {
		unset( $data['author_name'], $data['author_url'] );
		return $data;
	} );
	add_filter( 'wp_sitemaps_add_provider', static function ( $provider, $name ) {
		return 'users' === $name ? false : $provider;
	}, 10, 2 );
}

/* ── 2. WordPress version ──
 * The <meta name="generator"> and the feed <generator> go away (same filter). In the ?ver= of core files
 * the version becomes a short hash of it: still different at every update, so browser caches still renew.
 * It does not make the site safer by itself: it only gives less help to whoever looks for outdated sites.
 * What matters is keeping WordPress updated. */
if ( WPCF_VERSION ) {
	remove_action( 'wp_head', 'wp_generator' );
	add_filter( 'the_generator', '__return_empty_string' );
	$wpcf_ver = static function ( $src ) {
		$wp = get_bloginfo( 'version' );
		if ( $src && false !== strpos( $src, 'ver=' . $wp ) ) {
			$src = str_replace( 'ver=' . $wp, 'ver=' . substr( md5( $wp . wp_salt( 'nonce' ) ), 0, 8 ), $src );
		}
		return $src;
	};
	add_filter( 'script_loader_src', $wpcf_ver );
	add_filter( 'style_loader_src', $wpcf_ver );
}

/* ── 3. XML-RPC ──
 * Old remote-publishing interface, today used mostly by bots (password guessing, pingback abuse).
 * xmlrpc.php loads WordPress, so mu-plugins, before handling the request: here it gets a 403.
 * Jetpack and some mobile apps need it: with Jetpack active the block is skipped. */
// Jetpack active on this site, or network-activated on a multisite.
$wpcf_jetpack = in_array( 'jetpack/jetpack.php', (array) get_option( 'active_plugins', [] ), true )
	|| ( is_multisite() && isset( ( (array) get_site_option( 'active_sitewide_plugins', [] ) )['jetpack/jetpack.php'] ) );
if ( WPCF_XMLRPC && ! $wpcf_jetpack ) {
	if ( defined( 'XMLRPC_REQUEST' ) && XMLRPC_REQUEST ) {
		status_header( 403 );
		header( 'Content-Type: text/plain; charset=utf-8' );
		exit( 'XML-RPC is disabled on this site.' );
	}
	// The EditURI link in the page head points to xmlrpc.php: with XML-RPC off, nothing to announce.
	remove_action( 'wp_head', 'rsd_link' );
	add_filter( 'xmlrpc_enabled', '__return_false' );
}

/* ── 4. Security headers ──
 * Sent by WordPress, so on pages, posts, archives and feeds (not on images, CSS, JS: FIXES.md has the
 * server rules for those). /embed/ pages exist to be shown inside other sites: no frame limits there.
 * HSTS without includeSubDomains or preload: only this host, and reversible.
 * The CSP is a minimal one that rarely breaks a site; a strict CSP must be built and tested by hand.
 * template_redirect (not send_headers): WordPress already knows the page, so is_embed() works.
 * If the server or the hosting panel already sends these headers, set WPCF_HEADERS to false: one source is
 * enough, two may send the same header twice. HSTS is remembered by browsers for a year (max-age): turn it on
 * only when HTTPS is there to stay. */
if ( WPCF_HEADERS ) {
	add_action( 'template_redirect', static function () {
		if ( headers_sent() ) {
			return;
		}
		header_remove( 'X-Powered-By' );
		header( 'X-Content-Type-Options: nosniff' );
		header( 'Referrer-Policy: strict-origin-when-cross-origin' );
		header( 'Permissions-Policy: camera=(), microphone=(), geolocation=(), payment=(), usb=()' );
		if ( is_embed() ) {
			header( 'Content-Security-Policy: upgrade-insecure-requests' );
		} else {
			header( 'X-Frame-Options: SAMEORIGIN' );
			header( "Content-Security-Policy: frame-ancestors 'self'; upgrade-insecure-requests" );
		}
		// Behind a proxy (e.g. Cloudflare) WordPress may not see HTTPS: the proxy header counts too.
		if ( is_ssl() || 'https' === strtolower( (string) ( $_SERVER['HTTP_X_FORWARDED_PROTO'] ?? '' ) ) ) {
			header( 'Strict-Transport-Security: max-age=31536000' );
		}
	}, 0 );
}
