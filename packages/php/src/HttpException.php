<?php
declare(strict_types=1);
namespace Litportnet\FreeProxy;
class HttpException extends FreeProxyException { public function __construct(public readonly int $status) { parent::__construct("Snapshot request failed with HTTP {$status}"); } }
