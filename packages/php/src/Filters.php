<?php
declare(strict_types=1);

namespace Litportnet\FreeProxy;

final readonly class Filters
{
    public function __construct(
        public ?string $protocol = null, public ?string $country = null, public ?string $anonymity = null,
        public ?bool $https = null, public ?int $maxLatencyMs = null, public ?int $minUptime7d = null,
        public ?int $minChecks7d = null, public int $checkedWithinMin = 30, public ?int $limit = null,
    ) {}
}
