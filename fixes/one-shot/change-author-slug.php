<?php
/**
 * Plugin Name: wp-check one-shot: change author slug
 * Description: Changes the public address of an author (/author/…/) without touching the login name. Runs once, then deletes itself.
 * License:     GPLv3
 *
 * WordPress makes the author slug (user_nicename) from the login name: whoever opens /author/mario-rossi/
 * already knows the name to log in with. Closing the users API, ?author=, oEmbed and the author sitemap
 * stops the ways to LIST users, but the slug still shows where the site itself uses it: the author link
 * in posts (if the theme shows it) and the CSS class of comments written by registered users
 * (comment-author-mario-rossi). If the theme shows no author and authors never comment, this is optional.
 *
 * Use: set $new_slug below in a text editor, upload the file to wp-content/mu-plugins/ by FTP or the hosting
 * file manager (or from the dashboard with MustUse Manager: https://salvatorenoschese.it/mustuse-manager-wordpress-plugin/), open the dashboard as an
 * administrator, read the green notice. The file deletes itself (if it cannot, the notice says so).
 * Login name, password, posts and roles do not change. The old /author/old-slug/ becomes a 404.
 */

defined( 'ABSPATH' ) || exit;

add_action( 'admin_init', static function () {

	// --- Settings -----------------------------------------------------------
	$new_slug = '';   // lowercase letters, numbers and dashes; different from the login name
	$user_id  = 0;    // 0 = the user who opens the dashboard; otherwise the user ID
	// --------------------------------------------------------------------------

	$flag = 'wpcf_change_author_slug_done';
	if ( ! current_user_can( 'manage_options' ) ) {
		return;
	}
	$notice = static function ( $type, $html ) {
		add_action( 'admin_notices', static function () use ( $type, $html ) {
			echo '<div class="notice notice-' . esc_attr( $type ) . '"><p><strong>Change author slug:</strong> ' . $html . '</p></div>';
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
	if ( get_option( $flag ) ) {   // already done (the file could not delete itself last time)
		$self_delete();
		return;
	}

	$user_id = $user_id ?: get_current_user_id();
	$user    = get_userdata( $user_id );
	$slug    = sanitize_title( $new_slug );

	$error = '';
	if ( ! $user ) {
		$error = 'user not found';
	} elseif ( '' === $slug ) {
		$error = 'new slug empty: set $new_slug in the file';
	} elseif ( $slug === sanitize_title( $user->user_login ) ) {
		$error = 'the new slug is the login name: pick another one';
	} elseif ( ( $other = get_user_by( 'slug', $slug ) ) && (int) $other->ID !== (int) $user_id ) {
		$error = 'the slug is already used by another user';
	}
	if ( $error ) {
		$notice( 'error', esc_html( $error ) . '. Nothing changed.' );
		return;
	}

	$old    = $user->user_nicename;
	$result = wp_update_user( [ 'ID' => $user_id, 'user_nicename' => $slug ] );
	if ( is_wp_error( $result ) ) {
		$notice( 'error', 'failed: ' . esc_html( $result->get_error_message() ) );
		return;
	}

	update_option( $flag, current_time( 'mysql' ), false );
	$notice( 'success', sprintf( '<code>/author/%s/</code> → <code>/author/%s/</code>. The login name did not change.', esc_html( $old ), esc_html( $slug ) ) );
	$self_delete();
} );
