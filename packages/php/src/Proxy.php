<?php
declare(strict_types=1);

namespace Litportnet\FreeProxy;

final readonly class Proxy
{
    public function __construct(
        public string $protocol, public string $ip, public int $port, public string $url,
        public ?string $country, public ?string $region, public ?string $city, public ?string $timezone,
        public ?int $asn, public ?string $asnOrg, public string $anonymity, public ?bool $https,
        public ?float $latencyMs, public ?float $latencyMedianMs, public ?float $uptime24h, public ?float $uptime7d,
        public int $checks7d, public ?string $exitIp, public int $sourcesCount, public string $firstSeen, public string $lastChecked,
    ) {}
}
