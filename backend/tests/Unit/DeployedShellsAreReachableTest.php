<?php

declare(strict_types=1);

namespace Tests\Unit;

use PHPUnit\Framework\Attributes\Test;
use PHPUnit\Framework\TestCase;

/**
 * What a browser can actually fetch from the deployed stack.
 *
 * Every assertion here exists because the opposite was true in a running
 * deployment and nothing noticed. The stack booted, health checks returned 200
 * and the test suite was green while the customer app ran a month-old bundle
 * and both operator shells served a blank page. None of those are states a
 * process-level check can see: they live in the three lines of nginx config and
 * two lines of Vite config that decide what a URL resolves to.
 *
 * These are text assertions over configuration, which is weaker than fetching
 * the URLs. They are here because they run on every push and the deployment
 * does not. The authoritative check is still a curl against the running box,
 * and deploy/README.md says which ones.
 */
final class DeployedShellsAreReachableTest extends TestCase
{
    private const REPOSITORY_ROOT = __DIR__.'/../../..';

    private function nginxConfig(): string
    {
        $path = self::REPOSITORY_ROOT.'/deploy/nginx/app.conf';
        self::assertFileExists($path, 'The site config the web image ships is missing.');

        return (string) file_get_contents($path);
    }

    /**
     * A Flutter web build writes main.dart.js, flutter.js, flutter_bootstrap.js
     * and flutter_service_worker.js under those exact names every time. A cache
     * directive that tells the browser not to revalidate is therefore a
     * directive to keep the first build it ever saw — which is what happened:
     * a corrected bundle sat on the server for as long as it took to notice,
     * while the browser kept running the broken one and reporting a network
     * error with no hint that the file was stale.
     */
    #[Test]
    public function the_customer_apps_unfingerprinted_files_are_never_marked_immutable(): void
    {
        foreach ($this->locationBlocksServingFrom($this->nginxConfig(), '/var/www/customer') as $header => $body) {
            self::assertStringNotContainsString(
                'immutable',
                $body,
                sprintf(
                    'The location "%s" serves the customer app and marks its files immutable. '
                    .'Flutter web does not fingerprint its output, so an immutable file name is '
                    .'reused by the next build and the browser never asks for it again.',
                    $header,
                ),
            );
        }
    }

    /**
     * nginx resolves a regex location before any plain prefix location, so a
     * rule matching \.js$ claims /restaurant/assets/index-<hash>.js out from
     * under `location /restaurant` and looks for it wherever that regex block's
     * root points. '^~' is the one thing that stops it.
     */
    #[Test]
    public function the_operator_shells_outrank_the_static_asset_regex(): void
    {
        $config = $this->nginxConfig();

        foreach (['/restaurant', '/admin'] as $path) {
            self::assertMatchesRegularExpression(
                '/location\s+\^~\s+'.preg_quote($path, '/').'\s/',
                $config,
                sprintf(
                    'location %s is not declared with "^~", so the static-asset regex outranks it '
                    .'and its bundle is looked for in the customer app\'s directory, where it 404s.',
                    $path,
                ),
            );
        }
    }

    /**
     * The API is a plain prefix in the same way, and an endpoint whose path
     * ends in .json would be looked for on disk rather than reaching Laravel.
     * No such endpoint exists today; this is about not needing to remember.
     */
    #[Test]
    public function the_api_outranks_the_static_asset_regex(): void
    {
        self::assertMatchesRegularExpression(
            '/location\s+\^~\s+\/api\s/',
            $this->nginxConfig(),
            'location /api is not declared with "^~", so a static-asset regex can claim an API path.',
        );
    }

    /**
     * The old config asserted HTTPS unconditionally because at the time a host
     * proxy always terminated TLS. Published on a plain port that became a
     * lie: Laravel generated https:// URLs for an origin reachable only over
     * http, and sent HSTS over a connection that had none.
     */
    #[Test]
    public function the_request_scheme_is_taken_from_the_request_not_assumed(): void
    {
        $config = $this->nginxConfig();

        self::assertDoesNotMatchRegularExpression(
            '/fastcgi_param\s+HTTPS\s+on\s*;/',
            $config,
            'HTTPS is hard-coded on. On a plain-HTTP deployment that makes every generated URL wrong.',
        );

        self::assertDoesNotMatchRegularExpression(
            '/fastcgi_param\s+REQUEST_SCHEME\s+https\s*;/',
            $config,
            'REQUEST_SCHEME is hard-coded to https rather than derived from the request.',
        );

        self::assertStringContainsString(
            '$http_x_forwarded_proto',
            $config,
            'Nothing reads X-Forwarded-Proto, so a TLS-terminating tunnel in front cannot be honoured.',
        );
    }

    /**
     * Vite emits root-absolute asset URLs unless told the app is served from a
     * sub-path. Both shells are served from one. Without `base`, their HTML
     * loads and asks for /assets/index-<hash>.js, which resolves into the
     * customer app's directory and 404s: a blank page, and no error anywhere
     * an operator would look.
     */
    #[Test]
    public function each_operator_shell_is_built_for_the_path_it_is_served_from(): void
    {
        foreach (['restaurant', 'admin'] as $app) {
            $path = self::REPOSITORY_ROOT."/web/apps/{$app}/vite.config.ts";
            self::assertFileExists($path);

            self::assertStringContainsString(
                "base: '/{$app}/'",
                (string) file_get_contents($path),
                sprintf(
                    'The %s shell has no base path, so its built HTML asks for /assets/... which is '
                    .'the customer app\'s directory. The page renders empty.',
                    $app,
                ),
            );
        }
    }

    /**
     * The mirror image of the above, and the reason both are asserted: an app
     * whose assets load from /restaurant/ but whose router still matches on /
     * fetches every file successfully and then renders nothing.
     */
    #[Test]
    public function each_operator_shells_router_uses_the_same_base(): void
    {
        foreach (['restaurant', 'admin'] as $app) {
            $path = self::REPOSITORY_ROOT."/web/apps/{$app}/src/main.tsx";
            self::assertFileExists($path);

            self::assertStringContainsString(
                'basename={import.meta.env.BASE_URL}',
                (string) file_get_contents($path),
                sprintf(
                    'The %s shell\'s router has no basename, so under its sub-path no route matches.',
                    $app,
                ),
            );
        }
    }

    /**
     * Splits the config into location blocks, brace-matched rather than
     * line-counted, and returns the ones rooted at a given directory. A regex
     * over the whole file would have said "immutable appears somewhere", which
     * is true and useless — it is correct for the Vite bundles.
     *
     * @return array<string, string> header line => block body
     */
    private function locationBlocksServingFrom(string $config, string $root): array
    {
        $blocks = [];
        $offset = 0;

        while (($start = strpos($config, 'location', $offset)) !== false) {
            $open = strpos($config, '{', $start);
            if ($open === false) {
                break;
            }

            $depth = 0;
            $end = $open;
            for ($i = $open, $length = strlen($config); $i < $length; $i++) {
                if ($config[$i] === '{') {
                    $depth++;
                } elseif ($config[$i] === '}') {
                    $depth--;
                    if ($depth === 0) {
                        $end = $i;
                        break;
                    }
                }
            }

            $header = trim(substr($config, $start, $open - $start));
            $body = substr($config, $open, $end - $open + 1);
            $offset = $end + 1;

            if (preg_match('/(?:root|alias)\s+'.preg_quote($root, '/').'/', $body) === 1) {
                $blocks[$header] = $body;
            }
        }

        self::assertNotEmpty(
            $blocks,
            sprintf('No location block serves from %s — the config or this test has drifted.', $root),
        );

        return $blocks;
    }
}
