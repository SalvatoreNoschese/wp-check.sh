<?php
/**
 * Plugin Name: wp-check one-shot: rename login
 * Description: Renames a login name (e.g. "admin") keeping the same user, password, posts and roles. Runs once, then deletes itself.
 * License:     GPLv3
 *
 * "admin" is the first name every bot tries. WordPress has no button to rename a login: the usual way is
 * a new administrator plus deleting the old one. This renames it in place instead. Only the login: the
 * author slug (the name in /author/…/) is a separate thing, changed by change-author-slug.php. If the
 * slug is still the old login (e.g. /author/admin/), the notice says so: run that script next.
 *
 * Edit the values below in a text editor first, then upload the file to wp-content/mu-plugins/ by FTP or
 * the hosting file manager (or from the dashboard with MustUse Manager: https://salvatorenoschese.it/mustuse-manager-wordpress-plugin/).
 * Before: a backup of the database, and make sure you KNOW the password. After the rename you must
 * log in with name and password: one-click logins (hosting panel buttons, magic links, test-site
 * services) may not work any more. No password? Set one first in Users → Profile.
 * Use: set the values below, upload the file to wp-content/mu-plugins/,
 * open the dashboard as an administrator, read the notice. The file deletes itself (if it cannot, the
 * notice says so). The renamed user is logged out everywhere: log in again with the NEW name and the
 * same password.
 */

defined( 'ABSPATH' ) || exit;

add_action( 'admin_init', static function () {
	global $wpdb;

	// --- Settings -----------------------------------------------------------
	$old_login = 'admin';  // current login name
	$new_login = '';       // new login name: not public anywhere, not the site or author name
	// --------------------------------------------------------------------------

	$flag = 'wpcf_rename_login_done';
	if ( ! current_user_can( 'manage_options' ) ) {
		return;
	}
	$notice = static function ( $type, $html ) {
		add_action( 'admin_notices', static function () use ( $type, $html ) {
			echo '<div class="notice notice-' . esc_attr( $type ) . '"><p><strong>Rename login:</strong> ' . $html . '</p></div>';
		} );
	};
	// Deleted: the flag is not needed any more. Not deleted: the flag stops a second run until it is.
	$self_delete = static function () use ( $notice, $flag ) {
		if ( @unlink( __FILE__ ) ) {
			delete_option( $flag );
		} else {
			$notice( 'warning', 'could not delete the file: remove <code>' . esc_html( basename( __FILE__ ) ) . '</code> from <code>wp-content/mu-plugins</code> by hand.' );
		}
	};
	if ( get_option( $flag ) ) {
		$self_delete();
		return;
	}

	$new   = sanitize_user( $new_login, true );
	$user  = get_user_by( 'login', $old_login );
	$error = '';
	if ( '' === $new || $new !== $new_login ) {
		$error = 'new login empty or with characters WordPress does not allow (letters, numbers, _ . - @): set $new_login in the file';
	} elseif ( strlen( $new ) > 60 || in_array( strtolower( $new ), [ 'admin', 'administrator', 'root', 'user', 'test', 'demo' ], true ) ) {
		$error = 'new login too long or too easy to guess';
	} elseif ( ! $user ) {
		$error = 'login "' . esc_html( $old_login ) . '" not found (already renamed?)';
	} elseif ( username_exists( $new ) ) {
		$error = 'login "' . esc_html( $new ) . '" already exists';
	}

	if ( $error ) {
		$notice( 'error', $error . '. Nothing changed.' );
		return;
	}

	// wp_update_user() cannot change user_login: a direct update, then the caches.
	if ( false === $wpdb->update( $wpdb->users, [ 'user_login' => $new ], [ 'ID' => $user->ID ] ) ) {
		$notice( 'error', 'database update failed. Nothing changed.' );
		return;
	}
	clean_user_cache( $user->ID );
	WP_Session_Tokens::get_instance( $user->ID )->destroy_all();

	// Multisite: super admins are stored by login name.
	if ( is_multisite() ) {
		$supers = (array) get_site_option( 'site_admins', [] );
		$i      = array_search( $old_login, $supers, true );
		if ( false !== $i ) {
			$supers[ $i ] = $new;
			update_site_option( 'site_admins', array_values( $supers ) );
		}
	}

	update_option( $flag, current_time( 'mysql' ), false );
	$msg  = sprintf( '"%s" is now "%s"', esc_html( $old_login ), esc_html( $new ) );
	$msg .= (int) $user->ID === get_current_user_id()
		? '. You will be asked to log in again: use the new name and the same password.'
		: '. That user must log in again with the new name and the same password.';
	$notice( 'success', $msg );
	// The slug is separate: if it still shows the old login, say what to do next.
	if ( $user->user_nicename === sanitize_title( $old_login ) ) {
		$notice( 'warning', sprintf( 'the author address is still <code>/author/%s/</code>: change it with <code>change-author-slug.php</code>.', esc_html( $user->user_nicename ) ) );
	}
	$self_delete();
} );
