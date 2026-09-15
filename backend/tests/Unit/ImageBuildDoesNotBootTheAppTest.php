<?php

declare(strict_types=1);

namespace Tests\Unit;

use App\Support\ProductionConfigGuard;
use PHPUnit\Framework\TestCase;

/**
 * No Dockerfile boots the application while building an image.
 *
 * WHY THIS EXISTS. `deploy/backend.Dockerfile` ran `composer dump-autoload`
 * without `--no-scripts`. Composer's post-autoload-dump hook runs
 * `artisan package:discover`, which boots Laravel — and at image-build time
 * there is no `.env`, so `APP_ENV` falls back to `production` and
 * {@see ProductionConfigGuard} refuses to start without a real SMS
 * vendor, Places, Routes, Razorpay and a pickup pepper. The build died on a page
 * of entirely correct complaints about credentials that have nothing to do with
 * building an image, twenty minutes into a deploy.
 *
 * The guard was right and the build was wrong. An image must not depend on
 * runtime configuration: the same image runs in review and in production, and it
 * cannot know which while it is being built.
 *
 * It survived unnoticed because the deployment had never once run — the workflow
 * skipped for want of credentials and reported green (KI-047). This test is what
 * makes the rule hold without a deploy to discover it.
 */
final class ImageBuildDoesNotBootTheAppTest extends TestCase
{
    /** @return list<string> */
    private function dockerfiles(): array
    {
        // backend/tests/Unit → backend/tests → backend → the repository root.
        $root = dirname(__DIR__, 3);
        $found = [];

        foreach (glob($root.'/deploy/*.Dockerfile') ?: [] as $path) {
            $found[] = $path;
        }

        return $found;
    }

    /**
     * Every RUN line, joined across backslash continuations.
     *
     * A multi-line RUN is one command, and reading it line by line would miss a
     * `composer dump-autoload` whose flags are on the next line — which is
     * exactly how the real one was written.
     *
     * @return list<string>
     */
    private function runCommands(string $contents): array
    {
        $joined = preg_replace('/\\\\\s*\n\s*/', ' ', $contents) ?? $contents;
        $commands = [];

        foreach (explode("\n", $joined) as $line) {
            $line = trim($line);

            if (str_starts_with($line, 'RUN ')) {
                $commands[] = $line;
            }
        }

        return $commands;
    }

    public function test_there_is_a_dockerfile_to_check(): void
    {
        // A glob that matches nothing passes every assertion below for free.
        self::assertNotEmpty(
            $this->dockerfiles(),
            'No deploy Dockerfile was found. Either they moved or this test is '
            .'scanning the wrong directory, and a guard that scans nothing is '
            .'worse than no guard.'
        );
    }

    public function test_no_build_step_invokes_artisan(): void
    {
        foreach ($this->dockerfiles() as $path) {
            foreach ($this->runCommands(file_get_contents($path) ?: '') as $command) {
                self::assertDoesNotMatchRegularExpression(
                    '/\bartisan\b/',
                    $command,
                    basename($path).' runs artisan while building the image: '
                    .$command
                    .' — that boots the app with no .env, so APP_ENV falls back '
                    .'to production and ProductionConfigGuard refuses. Whatever '
                    .'this command needs belongs at container start, not in the '
                    .'image.'
                );
            }
        }
    }

    public function test_composer_never_runs_its_scripts_during_a_build(): void
    {
        foreach ($this->dockerfiles() as $path) {
            foreach ($this->runCommands(file_get_contents($path) ?: '') as $command) {
                if (! str_contains($command, 'composer ')) {
                    continue;
                }

                // `composer --version` and friends run nothing. The two that do
                // are the ones that trigger hooks.
                if (! preg_match('/composer\s+(install|update|dump-autoload)\b/', $command)) {
                    continue;
                }

                self::assertStringContainsString(
                    '--no-scripts',
                    $command,
                    basename($path).' runs composer without --no-scripts: '
                    .$command
                    .' — post-autoload-dump calls artisan package:discover, '
                    .'which boots the app during the build. Laravel regenerates '
                    .'bootstrap/cache/packages.php on first boot instead.'
                );
            }
        }
    }
}
