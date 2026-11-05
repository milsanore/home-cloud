<?php
/**
 * Plugin Name: home-cloud hardening
 * Description: Managed in git (home-cloud/config/wordpress). Disables XML-RPC and anonymous username enumeration.
 */

defined('ABSPATH') || exit;

// XML-RPC off (also blocked at the proxy)
add_filter('xmlrpc_enabled', '__return_false');
add_filter('xmlrpc_methods', '__return_empty_array');
add_filter('wp_headers', function ($headers) {
    unset($headers['X-Pingback']);
    return $headers;
});

// REST API: hide the users endpoints from anonymous visitors (the editor still works when logged in)
add_filter('rest_endpoints', function ($endpoints) {
    if (is_user_logged_in()) {
        return $endpoints;
    }
    foreach (array_keys($endpoints) as $route) {
        if (strpos($route, '/wp/v2/users') === 0) {
            unset($endpoints[$route]);
        }
    }
    return $endpoints;
});

// ?author=N redirects to /author/<username>/ - stop that for anonymous visitors
add_action('init', function () {
    if (!is_admin() && !is_user_logged_in() && isset($_GET['author'])) {
        wp_safe_redirect(home_url('/'), 301);
        exit;
    }
});
