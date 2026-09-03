<?php

declare(strict_types=1);

namespace Tests\Unit;

use App\Support\ProductionConfigGuard;
use Illuminate\Foundation\Application;
use RuntimeException;
use Tests\TestCase;

/**
 * Each case here is a configuration that would otherwise produce a service that
 * looks healthy and is not.
 */
final class ProductionConfigGuardTest extends TestCase
{
    private function appIn(string $environment): Application
    {
        $app = $this->app;
        $app['env'] = $environment;
        config(['app.env' => $environment]);

        return $app;
    }

    private function validProductionConfig(): void
    {
        config([
            'app.debug' => false,
            'app.key' => 'base64:'.base64_encode(random_bytes(32)),
            'foodonthego.frontend_urls' => ['https://dashboard.foodonthego.example'],
            'database.default' => 'mysql',
            'database.connections.mysql.password' => 'a-real-password',
        ]);
    }

    public function test_a_correctly_configured_production_boots(): void
    {
        $this->validProductionConfig();

        ProductionConfigGuard::assert($this->appIn('production'));

        $this->addToAssertionCount(1);
    }

    public function test_local_development_is_not_subject_to_these_rules(): void
    {
        config(['app.debug' => true, 'foodonthego.frontend_urls' => []]);

        ProductionConfigGuard::assert($this->appIn('local'));

        $this->addToAssertionCount(1);
    }

    public function test_debug_mode_stops_production_from_starting(): void
    {
        $this->validProductionConfig();
        config(['app.debug' => true]);

        $this->expectException(RuntimeException::class);
        $this->expectExceptionMessageMatches('/APP_DEBUG/');

        ProductionConfigGuard::assert($this->appIn('production'));
    }

    public function test_a_missing_app_key_stops_production_from_starting(): void
    {
        $this->validProductionConfig();
        config(['app.key' => '']);

        $this->expectExceptionMessageMatches('/APP_KEY/');

        ProductionConfigGuard::assert($this->appIn('production'));
    }

    public function test_an_empty_cors_list_stops_production_from_starting(): void
    {
        $this->validProductionConfig();
        config(['foodonthego.frontend_urls' => []]);

        $this->expectExceptionMessageMatches('/FRONTEND_URLS/');

        ProductionConfigGuard::assert($this->appIn('production'));
    }

    public function test_a_wildcard_origin_stops_production_from_starting(): void
    {
        $this->validProductionConfig();
        config(['foodonthego.frontend_urls' => ['*']]);

        $this->expectExceptionMessageMatches('/wildcard/');

        ProductionConfigGuard::assert($this->appIn('production'));
    }

    public function test_a_plain_http_origin_stops_production_from_starting(): void
    {
        $this->validProductionConfig();
        config(['foodonthego.frontend_urls' => ['http://dashboard.foodonthego.example']]);

        $this->expectExceptionMessageMatches('/https/');

        ProductionConfigGuard::assert($this->appIn('production'));
    }

    public function test_a_non_mysql_default_connection_stops_production_from_starting(): void
    {
        $this->validProductionConfig();
        config(['database.default' => 'sqlite']);

        $this->expectExceptionMessageMatches('/mysql/');

        ProductionConfigGuard::assert($this->appIn('production'));
    }

    public function test_staging_is_guarded_the_same_way_as_production(): void
    {
        $this->validProductionConfig();
        config(['app.debug' => true]);

        $this->expectException(RuntimeException::class);

        ProductionConfigGuard::assert($this->appIn('staging'));
    }

    public function test_the_failure_message_names_every_problem_at_once(): void
    {
        $this->validProductionConfig();
        config(['app.debug' => true, 'app.key' => '', 'foodonthego.frontend_urls' => []]);

        try {
            ProductionConfigGuard::assert($this->appIn('production'));
            $this->fail('Expected the guard to refuse to boot.');
        } catch (RuntimeException $e) {
            // Fixing configuration one restart at a time is miserable; report all of it.
            $this->assertStringContainsString('APP_DEBUG', $e->getMessage());
            $this->assertStringContainsString('APP_KEY', $e->getMessage());
            $this->assertStringContainsString('FRONTEND_URLS', $e->getMessage());
        }
    }
}
