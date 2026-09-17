import 'dart:convert';
import 'dart:io';

import 'package:litportnet_free_proxy/litportnet_free_proxy.dart';
import 'package:test/test.dart';

final DateTime _now = DateTime.utc(2026, 9, 10);

Map<String, dynamic> _loadFixture() {
  final file = File('test/fixtures/api_snapshot.json');
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

LitportFreeProxyClient _clientFor(
  Object body, {
  int statusCode = 200,
  Duration timeout = const Duration(seconds: 10),
}) {
  final encoded = body is String ? body : jsonEncode(body);
  return LitportFreeProxyClient(
    now: () => _now,
    timeout: timeout,
    transport: (url, requestTimeout) async {
      return TransportResponse(
        statusCode: statusCode,
        headers: const {},
        body: encoded,
      );
    },
  );
}

Map<String, dynamic> _envelope(List<Map<String, dynamic>> proxies) {
  return {
    'generatedAt': _now.toIso8601String(),
    'count': proxies.length,
    'proxies': proxies,
  };
}

Map<String, dynamic> _sortRow({
  required String host,
  required int checks7d,
  required num uptime7d,
  required num responseTimeMs,
}) {
  return {
    'protocol': 'http',
    'host': host,
    'port': 80,
    'externalIp': host,
    'geoCountry': 'US',
    'geoRegion': null,
    'geoCity': null,
    'geoTimezone': null,
    'asn': null,
    'asnOrgName': null,
    'anonymity': 'elite',
    'https': null,
    'responseTimeMs': responseTimeMs,
    'responseTimeMedianMs': null,
    'uptime24h': null,
    'uptime7d': uptime7d,
    'checks7d': checks7d,
    'sourcesCount': 0,
    'createdAt': '2026-09-01T00:00:00.000Z',
    'pingAt': _now.toIso8601String(),
  };
}

void main() {
  test('normalizes the fixture and nulls low-sample uptime', () async {
    final client = _clientFor(_loadFixture());
    final rows = await client.getProxies();
    expect(rows, hasLength(5));
    expect(rows.first.url, 'http://8.8.8.8:8080');
    expect(rows.first.latencyMs, 120);
    expect(rows.first.asn, 15169);
    expect(rows.last.uptime7d, isNull);
    final germanRow = rows.firstWhere((row) => row.country == 'de');
    expect(germanRow.latencyMs, isNull);
    expect(germanRow.uptime7d, 80.0);
  });

  test('applies each filter', () async {
    final client = _clientFor(_loadFixture());
    expect(
      await client.getProxies(const ProxyFilters(protocol: 'socks5')),
      hasLength(1),
    );
    expect(
      await client.getProxies(const ProxyFilters(country: 'US')),
      hasLength(1),
    );
    expect(
      await client.getProxies(const ProxyFilters(anonymity: 'transparent')),
      hasLength(1),
    );
    expect(
      await client.getProxies(const ProxyFilters(https: false)),
      hasLength(2),
    );
    expect(
      await client.getProxies(const ProxyFilters(maxLatencyMs: 60)),
      hasLength(1),
    );
    expect(
      await client.getProxies(const ProxyFilters(minUptime7d: 96)),
      hasLength(1),
    );
    expect(
      await client.getProxies(const ProxyFilters(minChecks7d: 70)),
      hasLength(1),
    );
    expect(
      await client.getProxies(),
      hasLength(5),
      reason: 'default checkedWithinMin excludes the stale record',
    );
    expect(
      await client.getProxies(const ProxyFilters(checkedWithinMin: 45)),
      hasLength(6),
      reason: 'a wider checkedWithinMin includes the stale record',
    );
  });

  test('limits results after sorting', () async {
    final client = _clientFor(_loadFixture());
    expect(await client.getProxies(const ProxyFilters(limit: 0)), isEmpty);
    final top2 = await client.getProxies(const ProxyFilters(limit: 2));
    expect(top2.map((row) => row.url), [
      'http://8.8.8.8:8080',
      'http://51.5.0.10:3128',
    ]);
  });

  test('sorts by uptime, then latency, then URL', () async {
    final rows = [
      _sortRow(
        host: '1.9.9.9',
        checks7d: 50,
        uptime7d: 90,
        responseTimeMs: 50,
      ),
      _sortRow(
        host: '2.2.2.2',
        checks7d: 50,
        uptime7d: 90,
        responseTimeMs: 50,
      ),
      _sortRow(
        host: '3.3.3.3',
        checks7d: 50,
        uptime7d: 90,
        responseTimeMs: 100,
      ),
      _sortRow(
        host: '9.9.9.9',
        checks7d: 1,
        uptime7d: 99,
        responseTimeMs: 10,
      ),
    ];
    final client = _clientFor(_envelope(rows));
    final result = await client.getProxies();
    expect(result.map((row) => row.url), [
      'http://1.9.9.9:80',
      'http://2.2.2.2:80',
      'http://3.3.3.3:80',
      'http://9.9.9.9:80',
    ]);
  });

  test('pickBest returns at most n top-ranked results', () async {
    final client = _clientFor(_loadFixture());
    final top2 = await client.pickBest(2);
    expect(top2.map((row) => row.url), [
      'http://8.8.8.8:8080',
      'http://51.5.0.10:3128',
    ]);
    expect(await client.pickBest(100), hasLength(5));
    await expectLater(
      client.pickBest(-1),
      throwsA(isA<FilterValidationException>()),
    );
  });

  test('rejects invalid filters', () async {
    final client = _clientFor(_loadFixture());
    for (final filters in [
      const ProxyFilters(protocol: 'bogus'),
      const ProxyFilters(country: 'usa'),
      const ProxyFilters(anonymity: 'invisible'),
      const ProxyFilters(maxLatencyMs: -1),
      const ProxyFilters(minUptime7d: -1),
      const ProxyFilters(minChecks7d: -1),
      const ProxyFilters(limit: -1),
      const ProxyFilters(checkedWithinMin: 0),
      const ProxyFilters(checkedWithinMin: 1441),
    ]) {
      await expectLater(
        client.getProxies(filters),
        throwsA(isA<FilterValidationException>()),
      );
    }
  });

  test('rejects a truncated envelope', () async {
    final client = _clientFor({
      'generatedAt': _now.toIso8601String(),
      'count': 0,
      'truncated': true,
      'proxies': <Map<String, dynamic>>[],
    });
    await expectLater(
      client.getProxies(),
      throwsA(isA<SnapshotTruncatedException>()),
    );
  });

  test('rejects a count that does not match the proxies list', () async {
    final client = _clientFor({
      'generatedAt': _now.toIso8601String(),
      'count': 99,
      'proxies': <Map<String, dynamic>>[],
    });
    await expectLater(
      client.getProxies(),
      throwsA(isA<SnapshotValidationException>()),
    );
  });

  test('rejects a stale generatedAt', () async {
    final stale = _now.subtract(const Duration(seconds: 121));
    final client = _clientFor({
      'generatedAt': stale.toIso8601String(),
      'count': 0,
      'proxies': <Map<String, dynamic>>[],
    });
    await expectLater(
      client.getProxies(),
      throwsA(isA<SnapshotValidationException>()),
    );
  });

  test('raises HttpStatusException for a non-2xx response', () async {
    final client = _clientFor(
      {'generatedAt': _now.toIso8601String(), 'count': 0, 'proxies': []},
      statusCode: 500,
    );
    await expectLater(
      client.getProxies(),
      throwsA(
        isA<HttpStatusException>().having(
          (error) => error.statusCode,
          'statusCode',
          500,
        ),
      ),
    );
  });

  test('propagates a transport timeout and forwards the timeout', () async {
    Duration? receivedTimeout;
    final client = LitportFreeProxyClient(
      now: () => _now,
      timeout: const Duration(milliseconds: 1500),
      transport: (url, timeout) async {
        receivedTimeout = timeout;
        throw const ProxyTimeoutException(
          'Snapshot request timed out after 1.5s',
        );
      },
    );
    await expectLater(
      client.getProxies(),
      throwsA(isA<ProxyTimeoutException>()),
    );
    expect(receivedTimeout, const Duration(milliseconds: 1500));
  });

  test('rejects malformed JSON', () async {
    final client = _clientFor('{"broken');
    await expectLater(
      client.getProxies(),
      throwsA(isA<SnapshotValidationException>()),
    );
  });

  test('rejects a non-public IPv4 host', () async {
    final fixture = _loadFixture();
    final proxies = List<Map<String, dynamic>>.from(fixture['proxies']);
    proxies[0] = Map<String, dynamic>.from(proxies[0])
      ..['host'] = '127.0.0.1';
    fixture['proxies'] = proxies;
    final client = _clientFor(fixture);
    await expectLater(
      client.getProxies(),
      throwsA(isA<SnapshotValidationException>()),
    );
  });
}
