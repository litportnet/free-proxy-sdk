<?php
declare(strict_types=1);
require_once __DIR__ . '/../vendor/autoload.php';

use Litportnet\FreeProxy\{Client, Filters, HttpException, SnapshotTruncatedException, SnapshotValidationException, TimeoutException};

$fixture = json_decode(file_get_contents(__DIR__ . '/fixtures/api-snapshot.json'), true, 512, JSON_THROW_ON_ERROR);
$now = static fn(): DateTimeImmutable => new DateTimeImmutable('2026-09-10T00:00:00Z');
$transport = static fn(string $_url, array $_headers, float $_timeout): array => [200, [], $fixture];
$client = new Client(transport: $transport, now: $now);
$rows = $client->getProxies();
assert(count($rows) === 2);
assert($rows[0]->url === 'http://8.8.8.8:8080');
assert($rows[0]->latencyMs === 120.0);
assert($rows[1]->uptime7d === null, 'uptime7d must be null when checks7d is below 50');
assert(count($client->getProxies(new Filters(protocol: 'socks5'))) === 1);
assert(count($client->getProxies(new Filters(minUptime7d: 90))) === 1);
assert(count($client->pickBest(1)) === 1);

$assertThrows = static function (string $class, callable $fn): void { try { $fn(); } catch (Throwable $e) { assert($e instanceof $class, $e::class); return; } throw new RuntimeException("Expected {$class}"); };
$assertThrows(HttpException::class, fn() => (new Client(transport: static fn() => [429, [], '[]'], now: $now))->getProxies());
$assertThrows(SnapshotTruncatedException::class, fn() => (new Client(transport: static fn() => [200, [], ['generatedAt' => '2026-09-10T00:00:00Z', 'count' => 0, 'truncated' => true, 'proxies' => []]], now: $now))->getProxies());
$assertThrows(SnapshotValidationException::class, fn() => (new Client(transport: static fn() => [200, [], ['generatedAt' => '2026-09-09T23:57:00Z', 'count' => 0, 'proxies' => []]], now: $now))->getProxies());
$timeout = new Client(timeout: 1.25, transport: static function (string $_url, array $_headers, float $seconds): array { assert($seconds === 1.25); throw new TimeoutException('Snapshot request timed out after 1.25s'); }, now: $now);
$assertThrows(TimeoutException::class, fn() => $timeout->getProxies());
assert($rows[0]->asn === 15169);
assert($client->getProxies(['limit' => 0]) === []);
assert(count($client->getProxies(['country' => 'US'])) === 1);
$fromBody = static fn(array|string $body) => new Client(transport: static fn() => [200, [], $body], now: $now);
foreach (['count' => 99, 'generatedAt' => '2026-09-10T00:00:06Z', 'proxies' => ['bad' => $fixture['proxies'][0]]] as $key => $value) {
    $bad = $fixture; $bad[$key] = $value;
    $assertThrows(SnapshotValidationException::class, fn() => $fromBody($bad)->getProxies());
}
foreach (['host' => '127.0.0.1', 'port' => '8080', 'asn' => true, 'geoCountry' => 123, 'responseTimeMs' => INF, 'pingAt' => '2026-09-10T00:00:00', 'createdAt' => '2026-02-30T00:00:00Z'] as $key => $value) {
    $bad = $fixture; $bad['proxies'][0][$key] = $value;
    $assertThrows(SnapshotValidationException::class, fn() => $fromBody($bad)->getProxies());
}
$assertThrows(SnapshotValidationException::class, fn() => $fromBody('{broken')->getProxies());
$bad = $fixture; $bad['proxies'][0]['pingAt'] = '2026-09-09T23:29:59Z';
assert(count($fromBody($bad)->getProxies()) === 1);
foreach ([['https' => 'yes'], ['checkedWithinMin' => 0], ['limit' => -1], ['unknown' => 1]] as $filters) {
    $assertThrows(\Litportnet\FreeProxy\FilterValidationException::class, fn() => $client->getProxies($filters));
}
fwrite(STDOUT, "PHP SDK tests passed\n");
