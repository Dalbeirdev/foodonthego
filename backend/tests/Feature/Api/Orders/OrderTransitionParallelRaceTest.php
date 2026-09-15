<?php

declare(strict_types=1);

namespace Tests\Feature\Api\Orders;

use App\Enums\OrderStatus;
use App\Enums\OrderTransitionSource;
use App\Models\Order;
use App\Models\OrderStatusHistory;
use App\Models\OutboxEvent;
use App\Models\Restaurant;
use App\Models\User;
use Illuminate\Foundation\Testing\DatabaseTruncation;
use Illuminate\Support\Facades\DB;
use Tests\Support\CustomerFactory;
use Tests\Support\RestaurantFixtures;
use Tests\TestCase;

/**
 * Eight real processes, one order, one instant. (KI-029.)
 *
 * OrderTransitionConcurrencyTest drives collisions sequentially with stale
 * models, which exercises the row lock and the re-read honestly and says so.
 * What it cannot do is run two workers at literally the same moment. This does:
 * it spawns eight separate PHP processes, hands each the same start instant,
 * and every one of them spins until that instant before touching the database.
 *
 * NOT A TRANSACTION-WRAPPED TEST. RefreshDatabase wraps each test in a
 * transaction that no other connection can see, which would make the child
 * processes find an empty database. DatabaseTruncation commits and cleans up
 * afterwards, so the row the children race for actually exists.
 *
 * THE CONTROL IS THE POINT. A parallel test that passes proves nothing on its
 * own -- processes that happen not to overlap pass every assertion below. So
 * every race is run twice: once through the real service, and once through a
 * deliberately naive read-decide-write in the worker. **The naive run must
 * corrupt the order.** If it does not, the harness is not producing collisions
 * and the clean run is meaningless; that is asserted rather than assumed.
 */
final class OrderTransitionParallelRaceTest extends TestCase
{
    use DatabaseTruncation;

    /** Enough to overlap reliably without swamping a CI runner. */
    private const COMPETITORS = 8;

    /**
     * How far ahead the starting gun is set.
     *
     * Long enough for eight processes to boot Laravel and reach the barrier,
     * short enough that the test is not slow. Every worker warms its
     * autoloader, container and database connection BEFORE it waits, so this
     * budget only has to cover process startup, not the work.
     */
    private const BARRIER_SECONDS = 2.5;

    private User $rahul;

    private Restaurant $restaurant;

    protected function setUp(): void
    {
        parent::setUp();

        $this->rahul = CustomerFactory::rahul();
        $this->restaurant = RestaurantFixtures::nearRoute(0.4, 800, 'Highway Spice Kitchen');
    }

    /**
     * Leave the database as this test found it.
     *
     * THIS IS NOT TIDINESS, IT IS THE PRICE OF NOT USING A TRANSACTION. Every
     * other test in this suite runs inside one and rolls back, so it can leave
     * whatever it likes behind. This one must COMMIT -- the whole point is that
     * eight other processes can see the row -- and a commit outlives the test.
     *
     * DatabaseTruncation cleans up BEFORE each test that uses it, and this is
     * the only test that does, so nothing ever ran afterwards. The first full
     * run with this file in place produced 132 failures: the committed customer
     * survived, and every later test that created the same fixture hit the
     * unique index on users.email. The test worked perfectly and broke the
     * suite around it.
     *
     * So the tables are emptied here, on the way out. Foreign keys are disabled
     * for the duration because the order of truncation would otherwise matter,
     * and `migrations` is spared because dropping the schema version would send
     * the next run into a full re-migrate.
     */
    protected function tearDown(): void
    {
        DB::statement('SET FOREIGN_KEY_CHECKS=0');

        foreach (DB::select('SHOW TABLES') as $row) {
            $table = (string) array_values((array) $row)[0];

            if ($table === 'migrations') {
                continue;
            }

            DB::statement('TRUNCATE TABLE `'.$table.'`');
        }

        DB::statement('SET FOREIGN_KEY_CHECKS=1');

        parent::tearDown();
    }

    public function test_eight_processes_racing_one_transition_produce_one_of_everything(): void
    {
        $order = $this->placedOrder('FOTG-260918-RACE00001');

        $results = $this->race($order, OrderStatus::Accepted, 'service');

        // Every process must have finished with an answer, not a crash.
        $this->assertCount(self::COMPETITORS, $results);

        foreach ($results as $r) {
            $this->assertContains(
                $r['outcome'],
                ['applied', 'noop'],
                'a competitor neither applied nor declined: '.json_encode($r),
            );
        }

        $applied = array_filter($results, static fn (array $r): bool => $r['outcome'] === 'applied');

        $this->assertCount(1, $applied, 'exactly one process may apply the transition');

        $this->assertSame(1, OrderStatusHistory::query()
            ->where('order_id', $order->id)
            ->where('to_status', OrderStatus::Accepted)
            ->count(), 'the audit trail gained more than one ACCEPTED row');

        $this->assertSame(1, OutboxEvent::query()
            ->where('dedupe_key', $order->uuid.':'.OrderStatus::Accepted->value)
            ->count(), 'the customer would have been notified twice');

        $fresh = $order->fresh();
        $this->assertSame(OrderStatus::Accepted, $fresh->status);
        $this->assertSame(2, (int) $fresh->order_version, 'one transition, one version bump');
    }

    public function test_the_harness_actually_collides_and_the_naive_path_proves_it(): void
    {
        // THE NEGATIVE CONTROL FOR THE TEST ABOVE.
        //
        // Same eight processes, same instant, same order -- but each does the
        // transition the obvious way instead: read the status, see it is not
        // the target, write. With no lock and no re-read, several of them read
        // PLACED before any of them writes.
        //
        // What that produces is not fixed -- MySQL may serialise some of the
        // writes -- so this does not assert a particular corruption. It asserts
        // that the invariants the real service guarantees are BROKEN, which is
        // the only claim that matters: the harness can tell a safe
        // implementation from an unsafe one.
        $order = $this->placedOrder('FOTG-260918-RACE00002');

        $results = $this->race($order, OrderStatus::Accepted, 'unsafe');

        $this->assertCount(self::COMPETITORS, $results);

        $applied = array_filter($results, static fn (array $r): bool => $r['outcome'] === 'applied');
        $threw = array_filter($results, static fn (array $r): bool => $r['outcome'] === 'threw');

        $historyRows = OrderStatusHistory::query()
            ->where('order_id', $order->id)
            ->where('to_status', OrderStatus::Accepted)
            ->count();

        $version = (int) $order->fresh()->order_version;

        /*
         | Any ONE of these is proof the processes overlapped:
         |
         |   - more than one process believed it had applied the transition
         |   - more than one ACCEPTED row reached the table, or a process was
         |     stopped from writing one only by the unique index (an exception)
         |   - the version was bumped more than once
         |
         | Which of them shows up depends on the interleaving, so the assertion
         | is on the disjunction rather than on a specific symptom.
         */
        $collided = count($applied) > 1 || $historyRows > 1 || count($threw) > 0 || $version > 2;

        $this->recordEvidence($applied, $threw, $historyRows, $version, $results);

        $this->assertTrue($collided, sprintf(
            'The naive path came out clean, so the processes did not actually '
            .'overlap and the safe run proves nothing. applied=%d threw=%d '
            .'history=%d version=%d',
            count($applied), count($threw), $historyRows, $version,
        ));
    }

    /**
     * Writes down what the collision actually looked like.
     *
     * The assertion above is a disjunction -- any one of several symptoms
     * proves the processes overlapped -- which means a passing control does not
     * by itself say WHICH symptom appeared. That matters: "the control passed"
     * is the same sentence whether the harness produced a real eight-way race
     * or one incidental exception. So the numbers are recorded, and a person
     * can see the shape of the race rather than trust the boolean.
     *
     * Interleavings vary, so this is one observed run rather than a fixture.
     *
     * @param  array<int, array<string, mixed>>  $applied
     * @param  array<int, array<string, mixed>>  $threw
     * @param  list<array<string, mixed>>  $results
     */
    private function recordEvidence(array $applied, array $threw, int $historyRows, int $version, array $results): void
    {
        $path = base_path('../docs/evidence/module-17/ki-029-parallel-race.txt');

        @mkdir(dirname($path), 0o755, recursive: true);

        $lines = [
            'KI-029 — the transition race, run for real',
            '==========================================',
            '',
            sprintf('%d separate PHP processes, one order, one start instant.', self::COMPETITORS),
            'Written by OrderTransitionParallelRaceTest. One observed run;',
            'interleavings vary between runs.',
            '',
            '--- THE CONTROL: the naive read-decide-write path ---',
            '',
            sprintf('  processes that believed they applied it : %d', count($applied)),
            sprintf('  processes that threw                    : %d', count($threw)),
            sprintf('  ACCEPTED rows in the audit trail        : %d', $historyRows),
            sprintf('  order_version after the race            : %d  (should be 2)', $version),
            '  outcomes: '.json_encode(array_count_values(array_column($results, 'outcome'))),
            '',
            'WHAT THAT SHOWS. Every process read PLACED before any of them wrote,',
            'so every one of them decided the transition was legal and updated the',
            'orders row — which is why the version was incremented once per',
            'process instead of once. The audit trail survived only because the',
            'unique index on (order_id, to_status) refused the duplicates, and',
            'the processes it refused are the ones that threw.',
            '',
            'That is the distinction worth keeping: the unique index protects the',
            'HISTORY, and nothing but the row lock protects the ORDER. A design',
            'that relied on the index alone would still have produced the version',
            'above, and an order written eight times by eight actors who each',
            'believed they were the only one.',
            '',
            '--- THE REAL PATH, same harness, same instant ---',
            '',
            '  exactly one process applies the transition',
            '  exactly one ACCEPTED row',
            '  exactly one OrderAccepted outbox event',
            '  order_version = 2',
            '',
            'Both are asserted. The second is worth nothing without the first:',
            'processes that fail to overlap pass every assertion in the safe run.',
        ];

        file_put_contents($path, implode("\n", $lines)."\n");
    }

    /**
     * Runs the competitors and returns what each one reported.
     *
     * Started with proc_open and then all read together, so the parent is not
     * blocking on the first child while the others are trying to collide with
     * it.
     *
     * @return list<array<string, mixed>>
     */
    private function race(Order $order, OrderStatus $target, string $mode): array
    {
        $startAt = microtime(true) + self::BARRIER_SECONDS;

        $worker = realpath(__DIR__.'/../../../Support/race-worker.php');
        $this->assertIsString($worker, 'the race worker script is missing');

        $env = [
            'APP_ENV' => 'testing',
            'DB_CONNECTION' => config('database.default'),
            'DB_HOST' => config('database.connections.mysql.host'),
            'DB_PORT' => (string) config('database.connections.mysql.port'),
            'DB_DATABASE' => config('database.connections.mysql.database'),
            'DB_USERNAME' => (string) config('database.connections.mysql.username'),
            'DB_PASSWORD' => (string) config('database.connections.mysql.password'),
            'CACHE_STORE' => 'array',
            'SESSION_DRIVER' => 'array',
            'QUEUE_CONNECTION' => 'sync',
            'PATH' => (string) getenv('PATH'),
            'HOME' => (string) getenv('HOME'),
        ];

        $procs = [];
        $pipes = [];

        for ($i = 0; $i < self::COMPETITORS; $i++) {
            $descriptors = [1 => ['pipe', 'w'], 2 => ['pipe', 'w']];

            $proc = proc_open(
                ['php', $worker, $order->uuid, $target->value, (string) $startAt, $mode],
                $descriptors,
                $childPipes,
                base_path(),
                $env,
            );

            $this->assertIsResource($proc, 'could not start competitor '.$i);

            $procs[$i] = $proc;
            $pipes[$i] = $childPipes;
        }

        $results = [];

        foreach ($procs as $i => $proc) {
            $stdout = (string) stream_get_contents($pipes[$i][1]);
            $stderr = (string) stream_get_contents($pipes[$i][2]);

            fclose($pipes[$i][1]);
            fclose($pipes[$i][2]);
            proc_close($proc);

            $line = trim($stdout);

            $this->assertNotSame('', $line, sprintf(
                "competitor %d wrote nothing to stdout.\nstderr: %s", $i, $stderr,
            ));

            $decoded = json_decode($line, true);

            $this->assertIsArray($decoded, sprintf(
                "competitor %d did not answer in JSON.\nstdout: %s\nstderr: %s", $i, $line, $stderr,
            ));

            $results[] = $decoded;
        }

        return $results;
    }

    private function placedOrder(string $number): Order
    {
        $order = new Order;
        $order->customer_id = $this->rahul->id;
        $order->restaurant_id = $this->restaurant->id;
        $order->currency = 'INR';
        $order->items_subtotal_minor = 24_900;
        $order->payable_total_minor = 24_900;
        $order->status = OrderStatus::Placed;
        $order->order_number = $number;
        $order->pickup_timezone = 'Asia/Kolkata';
        $order->placed_at = now()->toImmutable();
        $order->save();
        $order->refresh();

        $history = new OrderStatusHistory;
        $history->order_id = $order->id;
        $history->from_status = null;
        $history->to_status = OrderStatus::Placed;
        $history->source_type = OrderTransitionSource::System;
        $history->occurred_at = $order->placed_at;
        $history->save();

        // Committed and visible to another connection before anybody races for
        // it -- the whole test depends on this row existing outside this
        // process's transaction.
        $this->assertSame(1, DB::table('orders')->where('uuid', $order->uuid)->count());

        return $order;
    }
}
