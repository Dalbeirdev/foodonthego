<?php

declare(strict_types=1);

/**
 * One competitor in a transition race. Run as a real, separate PHP process.
 *
 * KI-029 said closing it "needs a test harness that can run parallel PHP
 * processes against one database". This is that process. The test spawns N of
 * these, each given the SAME start instant, and every one of them busy-waits
 * until that instant before touching the database — so they arrive together
 * rather than merely near each other.
 *
 * NOT AN ARTISAN COMMAND, deliberately. A console command is part of the
 * application's surface and would ship; this is a test fixture that happens to
 * need a process of its own, so it lives in tests/ and boots the framework
 * itself.
 *
 * ARGUMENTS
 *   1  order uuid
 *   2  target status value            e.g. ACCEPTED
 *   3  start instant, microtime(true) as a float string
 *   4  mode: "service" (the real path) or "unsafe" (see below)
 *
 * Writes one line of JSON to stdout describing what happened, so the parent can
 * tell a refusal apart from a crash.
 *
 * THE "unsafe" MODE IS THE NEGATIVE CONTROL AND THE REASON THIS FILE IS
 * TRUSTWORTHY. It performs the same transition the naive way -- read the
 * status, decide, write -- with no row lock and no re-read. If the harness is
 * genuinely making processes collide, that mode MUST produce a corrupt result;
 * if it comes out clean, then the processes are not actually overlapping and a
 * green result from "service" mode would mean nothing at all. The test asserts
 * both.
 */

use App\Enums\OrderStatus;
use App\Enums\OrderTransitionSource;
use App\Models\Order;
use App\Models\OrderStatusHistory;
use App\Services\Orders\OrderTransitionActor;
use App\Services\Orders\OrderTransitionService;
use Illuminate\Contracts\Console\Kernel;
use Illuminate\Foundation\Application;
use Illuminate\Support\Facades\DB;

require __DIR__.'/../../vendor/autoload.php';

/** @var Application $app */
$app = require __DIR__.'/../../bootstrap/app.php';
$app->make(Kernel::class)->bootstrap();

$uuid = (string) ($argv[1] ?? '');
$target = OrderStatus::from((string) ($argv[2] ?? ''));
$startAt = (float) ($argv[3] ?? 0);
$mode = (string) ($argv[4] ?? 'service');

$say = static function (array $payload): never {
    echo json_encode($payload, JSON_THROW_ON_ERROR), "\n";
    exit(0);
};

$order = Order::query()->where('uuid', $uuid)->first();

if ($order === null) {
    $say(['outcome' => 'no-order', 'mode' => $mode]);
}

/*
 | Everything above is warm-up: autoloading, the container, the first
 | connection. Doing it before the barrier is what makes the barrier mean
 | something -- otherwise the processes would be racing PHP's startup rather
 | than the transition.
 */
DB::connection()->getPdo();

// Spin, do not sleep. usleep() can overshoot by milliseconds, which at this
// scale is the whole window.
while (microtime(true) < $startAt) {
    // deliberately empty
}

$firedAt = microtime(true);

try {
    if ($mode === 'unsafe') {
        /*
         | The naive implementation, present ONLY so the harness can be shown to
         | catch it. Read, decide, write -- no lock, no re-read under it. This is
         | what the real service would be if OrderTransitionService had been
         | written alongside the first screen that needed it.
         */
        $current = OrderStatus::from((string) DB::table('orders')->where('id', $order->id)->value('status'));

        if ($current !== $target) {
            DB::table('orders')->where('id', $order->id)->update([
                'status' => $target->value,
                'order_version' => DB::raw('order_version + 1'),
            ]);

            $entry = new OrderStatusHistory;
            $entry->order_id = $order->id;
            $entry->from_status = $current;
            $entry->to_status = $target;
            $entry->source_type = OrderTransitionSource::TestHarness;
            $entry->occurred_at = now()->toImmutable();
            $entry->save();

            $say(['outcome' => 'applied', 'mode' => $mode, 'fired_at' => $firedAt]);
        }

        $say(['outcome' => 'skipped', 'mode' => $mode, 'fired_at' => $firedAt]);
    }

    $result = app(OrderTransitionService::class)->transition(
        $order,
        $target,
        OrderTransitionActor::testHarness(),
    );

    $say([
        'outcome' => $result->applied ? 'applied' : 'noop',
        'mode' => $mode,
        'version' => $result->version,
        'fired_at' => $firedAt,
    ]);
} catch (Throwable $e) {
    $say([
        'outcome' => 'threw',
        'mode' => $mode,
        'exception' => $e::class,
        'message' => $e->getMessage(),
        'fired_at' => $firedAt,
    ]);
}
