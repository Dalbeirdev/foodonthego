<?php

declare(strict_types=1);

namespace Tests\Unit;

use App\Services\Otp\OtpDeliveryProvider;
use App\Services\Otp\Providers\LogOtpProvider;
use App\Services\Places\DevelopmentGazetteerProvider;
use App\Services\Places\PlaceProvider;
use App\Services\Places\UnconfiguredPlaceProvider;
use App\Services\Routing\DevelopmentRouteProvider;
use App\Services\Routing\RouteProvider;
use App\Services\Routing\UnconfiguredRouteProvider;
use App\Support\ProductionConfigGuard;
use Illuminate\Foundation\Application;
use RuntimeException;
use Tests\Support\RecordingOtpProvider;
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
            'foodonthego.otp.simulate_provider_failure' => false,
        ]);

        // Stands in for a real SMS vendor: the only thing the guard asks a
        // provider is whether it can reach a handset.
        $this->app->instance(OtpDeliveryProvider::class, new RecordingOtpProvider(deliversToRealDevices: true));

        // And for a real place provider. The guard only asks whether one is
        // configured at all, so any implementation that is not the unconfigured
        // stand-in satisfies it.
        $this->app->instance(PlaceProvider::class, new DevelopmentGazetteerProvider(isProduction: false));

        // And for a real routing provider, for the same reason.
        $this->app->instance(RouteProvider::class, new DevelopmentRouteProvider(isProduction: false));
    }

    public function test_it_refuses_production_without_a_routing_provider(): void
    {
        $this->validProductionConfig();
        $this->app->instance(RouteProvider::class, new UnconfiguredRouteProvider);

        // Worse than the Places case. With no routing provider a deployment does
        // not merely fail — if the development stand-in were reachable there,
        // every customer would be shown a straight line across the countryside
        // with a distance and a travel time that were arithmetic rather than
        // roads. That is not a degraded product, it is a confidently wrong one.
        $this->expectException(RuntimeException::class);
        $this->expectExceptionMessageMatches('/ROUTE_PROVIDER is not configured/');

        ProductionConfigGuard::assert($this->appIn('production'));
    }

    public function test_the_development_route_provider_cannot_be_resolved_in_production(): void
    {
        $this->validProductionConfig();

        $app = $this->appIn('production');
        $app->bind(RouteProvider::class, fn (): RouteProvider => new DevelopmentRouteProvider(
            isProduction: true,
        ));

        $this->expectException(RuntimeException::class);
        $this->expectExceptionMessageMatches('/ROUTE_PROVIDER could not be resolved/');

        ProductionConfigGuard::assert($app);
    }

    public function test_production_refuses_to_boot_with_no_place_provider(): void
    {
        $this->validProductionConfig();
        $this->app->instance(PlaceProvider::class, new UnconfiguredPlaceProvider);

        $this->expectException(RuntimeException::class);
        $this->expectExceptionMessageMatches('/PLACES_PROVIDER is not configured/');

        ProductionConfigGuard::assert($this->appIn('production'));
    }

    public function test_the_development_gazetteer_refuses_to_exist_in_production(): void
    {
        // Two independent refusals, deliberately: the provider will not be
        // constructed, and the guard will not let the application boot if
        // something constructs one anyway.
        $this->expectException(RuntimeException::class);
        $this->expectExceptionMessageMatches('/never run in production/');

        new DevelopmentGazetteerProvider(isProduction: true);
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

    public function test_a_provider_that_cannot_reach_a_handset_stops_production_from_starting(): void
    {
        $this->validProductionConfig();
        $this->app->instance(OtpDeliveryProvider::class, new RecordingOtpProvider(deliversToRealDevices: false));

        // The failure this prevents: a release goes out still wired to a
        // development sender, every sign-in "succeeds" at the API, and no
        // customer ever receives a code.
        $this->expectExceptionMessageMatches('/does not deliver to real devices/');

        ProductionConfigGuard::assert($this->appIn('production'));
    }

    public function test_the_development_log_provider_refuses_to_exist_in_production(): void
    {
        $this->validProductionConfig();
        $this->app->bind(OtpDeliveryProvider::class, static fn (): LogOtpProvider => new LogOtpProvider('production'));

        // Two independent defences, and this asserts the inner one: even if the
        // guard were removed, the provider itself will not construct.
        $this->expectExceptionMessageMatches('/never be used in production/');

        ProductionConfigGuard::assert($this->appIn('production'));
    }

    public function test_the_simulated_failure_switch_stops_production_from_starting(): void
    {
        $this->validProductionConfig();
        config(['foodonthego.otp.simulate_provider_failure' => true]);

        $this->expectExceptionMessageMatches('/OTP_SIMULATE_PROVIDER_FAILURE/');

        ProductionConfigGuard::assert($this->appIn('production'));
    }
}
