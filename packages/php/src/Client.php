<?php
declare(strict_types=1);

namespace Litportnet\FreeProxy;

/** Synchronous client for the Litport API snapshot. */
final class Client
{
    public const DEFAULT_API_URL = 'https://litport.net/api/free-proxy/snapshot?checkedWithinMin=1440';
    /** @var null|callable(string,array<string,string>,float):array{0:int,1:array<string,string>,2:string|array<mixed>} */
    private $transport;
    /** @var callable():\DateTimeImmutable */
    private $now;

    public function __construct(private string $apiUrl = self::DEFAULT_API_URL, private float $timeout = 10.0, ?callable $transport = null, ?callable $now = null)
    {
        if (!is_finite($timeout) || $timeout <= 0) throw new FilterValidationException('timeout must be positive');
        $this->transport = $transport;
        $this->now = $now ?? static fn(): \DateTimeImmutable => new \DateTimeImmutable('now', new \DateTimeZone('UTC'));
    }

    /** @return list<Proxy> */
    public function getProxies(Filters|array|null $filters = null): array
    {
        $filters = $this->filters($filters);
        [$status, , $body] = $this->request();
        if ($status < 200 || $status >= 300) throw new HttpException($status);
        try { $snapshot = is_array($body) ? $body : json_decode($body, true, 512, JSON_THROW_ON_ERROR); }
        catch (\JsonException $e) { throw new SnapshotValidationException('Malformed snapshot JSON', 0, $e); }
        if (!is_array($snapshot) || !isset($snapshot['proxies']) || !is_array($snapshot['proxies']) || !array_is_list($snapshot['proxies'])) throw new SnapshotValidationException('Malformed snapshot envelope');
        if (($snapshot['truncated'] ?? false) === true) throw new SnapshotTruncatedException('Snapshot is truncated');
        if (!is_int($snapshot['count'] ?? null) || $snapshot['count'] !== count($snapshot['proxies']) || (isset($snapshot['truncated']) && !is_bool($snapshot['truncated']))) throw new SnapshotValidationException('Malformed snapshot envelope');
        $this->validateGeneratedAt($snapshot['generatedAt'] ?? null);
        $rows = array_map(fn(mixed $row): Proxy => $this->mapRow($row), $snapshot['proxies']);
        $now = ($this->now)(); $cutoff = $now->modify("-{$filters->checkedWithinMin} minutes");
        $rows = array_values(array_filter($rows, function (Proxy $row) use ($filters, $cutoff, $now): bool {
            $checked = $this->time($row->lastChecked); if ($checked < $cutoff || $checked > $now->modify('+5 seconds')) return false;
            return ($filters->protocol === null || $row->protocol === $filters->protocol)
                && ($filters->country === null || $row->country === $filters->country)
                && ($filters->anonymity === null || $row->anonymity === $filters->anonymity)
                && ($filters->https === null || $row->https === $filters->https)
                && ($filters->maxLatencyMs === null || ($row->latencyMs !== null && $row->latencyMs <= $filters->maxLatencyMs))
                && ($filters->minUptime7d === null || ($row->uptime7d !== null && $row->uptime7d >= $filters->minUptime7d))
                && ($filters->minChecks7d === null || $row->checks7d >= $filters->minChecks7d);
        }));
        usort($rows, static fn(Proxy $a, Proxy $b): int => [($a->uptime7d === null), -($a->uptime7d ?? 0), ($a->latencyMs === null), $a->latencyMs ?? 0, $a->url] <=> [($b->uptime7d === null), -($b->uptime7d ?? 0), ($b->latencyMs === null), $b->latencyMs ?? 0, $b->url]);
        return $filters->limit === null ? $rows : array_slice($rows, 0, $filters->limit);
    }

    /** @return list<Proxy> */
    public function pickBest(int $count, Filters|array|null $filters = null): array
    { if ($count < 0) throw new FilterValidationException('count must be a non-negative integer'); return array_slice($this->getProxies($filters), 0, $count); }
    public static function toProxyUrl(Proxy $proxy): string { return "{$proxy->protocol}://{$proxy->ip}:{$proxy->port}"; }

    /** @return array{0:int,1:array<string,string>,2:string|array<mixed>} */
    private function request(): array
    {
        if ($this->transport !== null) return ($this->transport)($this->apiUrl, [], $this->timeout);
        $context = stream_context_create(['http' => ['method' => 'GET', 'timeout' => $this->timeout, 'ignore_errors' => true]]);
        $body = @file_get_contents($this->apiUrl, false, $context);
        if ($body === false) {
            $message = error_get_last()['message'] ?? 'unknown transport error';
            if (str_contains(strtolower($message), 'timed out')) throw new TimeoutException("Snapshot request timed out after {$this->timeout}s");
            throw new RequestException("Snapshot request failed: {$message}");
        }
        $status = 200; foreach ($http_response_header ?? [] as $line) if (preg_match('#^HTTP/\\S+ (\\d+)#', $line, $match)) $status = (int)$match[1];
        return [$status, [], $body];
    }

    private function filters(Filters|array|null $input): Filters
    {
        try { $f = $input instanceof Filters ? $input : new Filters(...($input ?? [])); } catch (\Throwable $e) { throw new FilterValidationException('Invalid filters', 0, $e); }
        if ($f->protocol !== null && !in_array($f->protocol, ['http', 'socks4', 'socks5'], true)) throw new FilterValidationException('protocol must be http, socks4, or socks5');
        if ($f->country !== null && !preg_match('/^[a-zA-Z]{2}$/', $f->country)) throw new FilterValidationException('country must be a two-letter code');
        if ($f->anonymity !== null && !in_array($f->anonymity, ['transparent', 'anonymous', 'elite', 'unknown'], true)) throw new FilterValidationException('Invalid anonymity value');
        foreach ([$f->maxLatencyMs, $f->minUptime7d, $f->minChecks7d, $f->limit] as $v) if ($v !== null && $v < 0) throw new FilterValidationException('numeric filters must be non-negative');
        if ($f->checkedWithinMin < 1 || $f->checkedWithinMin > 1440) throw new FilterValidationException('checkedWithinMin must be from 1 to 1440');
        return new Filters($f->protocol, $f->country === null ? null : strtolower($f->country), $f->anonymity, $f->https, $f->maxLatencyMs, $f->minUptime7d, $f->minChecks7d, $f->checkedWithinMin, $f->limit);
    }

    private function mapRow(mixed $row): Proxy
    {
        if (!is_array($row)) throw new SnapshotValidationException('Snapshot contains an invalid proxy row');
        $get = static fn(string $key) => $row[$key] ?? null;
        $protocol = $get('protocol'); $ip = $get('host'); $port = $get('port'); $country = $get('geoCountry'); $asn = $get('asn');
        if (!is_string($protocol) || !in_array($protocol, ['http','socks4','socks5'], true) || !self::publicIpv4($ip) || !is_int($port) || $port < 1 || $port > 65535 || !is_string($get('anonymity')) || !in_array($get('anonymity'), ['transparent','anonymous','elite','unknown'], true)) throw new SnapshotValidationException('Snapshot contains an invalid proxy row');
        if ($country !== null && (!is_string($country) || !preg_match('/^[A-Za-z]{2}$/', $country))) throw new SnapshotValidationException('Invalid country');
        if (is_string($asn) && preg_match('/^AS(\\d+)$/', $asn, $m)) $asn = (int)$m[1];
        if ($asn !== null && (!is_int($asn) || $asn < 0)) throw new SnapshotValidationException('Invalid ASN');
        foreach (['geoRegion','geoCity','geoTimezone','asnOrgName','externalIp'] as $key) if ($get($key) !== null && !is_string($get($key))) throw new SnapshotValidationException('Invalid nullable string');
        if ($get('https') !== null && !is_bool($get('https'))) throw new SnapshotValidationException('Invalid https value');
        foreach (['responseTimeMs','responseTimeMedianMs','uptime24h','uptime7d'] as $key) if ($get($key) !== null && ((!is_int($get($key)) && !is_float($get($key))) || !is_finite((float)$get($key)))) throw new SnapshotValidationException('Invalid nullable number');
        if (!is_int($get('checks7d')) || $get('checks7d') < 0 || !is_int($get('sourcesCount')) || $get('sourcesCount') < 0) throw new SnapshotValidationException('Invalid count');
        $first = $this->iso($get('createdAt')); $last = $this->iso($get('pingAt')); if ($first === null || $last === null) throw new SnapshotValidationException('Invalid timestamp');
        $uptime = $get('checks7d') < 50 ? null : ($get('uptime7d') === null ? null : (float)$get('uptime7d'));
        return new Proxy($protocol, $ip, $port, "{$protocol}://{$ip}:{$port}", $country === null ? null : strtolower($country), $get('geoRegion'), $get('geoCity'), $get('geoTimezone'), $asn, $get('asnOrgName'), $get('anonymity'), $get('https'), $get('responseTimeMs') === null ? null : round((float)$get('responseTimeMs')), $get('responseTimeMedianMs') === null ? null : (float)$get('responseTimeMedianMs'), $get('uptime24h') === null ? null : (float)$get('uptime24h'), $uptime, $get('checks7d'), $get('externalIp'), $get('sourcesCount'), $first, $last);
    }

    private function validateGeneratedAt(mixed $value): void { $time = $this->iso($value); if ($time === null || $this->time($time) > ($this->now)()->modify('+5 seconds') || $this->time($time) < ($this->now)()->modify('-120 seconds')) throw new SnapshotValidationException('Snapshot generatedAt is outside the accepted window'); }
    private function iso(mixed $value): ?string { if (!is_string($value) || !preg_match('/^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}(?:\\.\\d{1,9})?(?:Z|[+-]\\d{2}:\\d{2})$/', $value)) return null; try { return $this->time($value)->format('Y-m-d\\TH:i:s.v\\Z'); } catch (\Throwable) { return null; } }
    private function time(string $value): \DateTimeImmutable { if (!preg_match('/^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}(?:\\.\\d{1,9})?(?:Z|[+-]\\d{2}:\\d{2})$/', $value)) throw new \InvalidArgumentException('Invalid ISO timestamp'); $parsed = new \DateTimeImmutable($value); $errors = \DateTimeImmutable::getLastErrors(); if ($errors !== false && ($errors['warning_count'] || $errors['error_count'])) throw new \InvalidArgumentException('Invalid ISO timestamp'); return $parsed->setTimezone(new \DateTimeZone('UTC')); }
    private static function publicIpv4(mixed $ip): bool { if (!is_string($ip) || filter_var($ip, FILTER_VALIDATE_IP, FILTER_FLAG_IPV4) === false) return false; $n = ip2long($ip); foreach ([['0.0.0.0',8],['10.0.0.0',8],['100.64.0.0',10],['127.0.0.0',8],['169.254.0.0',16],['172.16.0.0',12],['192.0.0.0',24],['192.0.2.0',24],['192.168.0.0',16],['198.18.0.0',15],['198.51.100.0',24],['203.0.113.0',24],['224.0.0.0',4],['240.0.0.0',4]] as [$net,$bits]) if (($n & (-1 << (32 - $bits))) === (ip2long($net) & (-1 << (32 - $bits)))) return false; return true; }
}
