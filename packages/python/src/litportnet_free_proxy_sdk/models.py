from dataclasses import dataclass
from typing import Optional

@dataclass(frozen=True)
class Proxy:
    protocol: str
    ip: str
    port: int
    url: str
    country: Optional[str]
    region: Optional[str]
    city: Optional[str]
    timezone: Optional[str]
    asn: Optional[int]
    asn_org: Optional[str]
    anonymity: str
    https: Optional[bool]
    latency_ms: Optional[float]
    latency_median_ms: Optional[float]
    uptime_24h: Optional[float]
    uptime_7d: Optional[float]
    checks_7d: int
    exit_ip: Optional[str]
    sources_count: int
    first_seen: str
    last_checked: str

@dataclass(frozen=True)
class Filters:
    protocol: Optional[str] = None
    country: Optional[str] = None
    anonymity: Optional[str] = None
    https: Optional[bool] = None
    max_latency_ms: Optional[int] = None
    min_uptime_7d: Optional[int] = None
    min_checks_7d: Optional[int] = None
    checked_within_min: int = 30
    limit: Optional[int] = None
