"""Synchronous, zero-runtime-dependency snapshot client for Python 3.9+."""
import json
import math
import re
import socket
from dataclasses import asdict
from datetime import datetime, timezone, timedelta
from time import monotonic
from typing import Any, Callable, Dict, Iterator, List, Optional, Tuple
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

from .fields_generated import FIELDS
from .models import Filters, Proxy

DEFAULT_API_URL = "https://litport.net/api/free-proxy/snapshot?checkedWithinMin=1440"
DEFAULT_GITHUB_URL = "https://raw.githubusercontent.com/litportnet/free-proxy-list/live/proxies/all.json"
PROTOCOLS = {"http", "socks4", "socks5"}
ANONYMITY = {"transparent", "anonymous", "elite", "unknown"}
FIELD_BY_PY = {field["python"]: field for field in FIELDS}

class FreeProxyError(Exception): pass
class TimeoutError(FreeProxyError): pass
class HttpError(FreeProxyError):
    def __init__(self, status: int, message: Optional[str] = None): self.status = status; super().__init__(message or "Snapshot request failed with HTTP %s" % status)
class NotModifiedWithoutCacheError(FreeProxyError): pass
class SnapshotValidationError(FreeProxyError): pass
class SnapshotTruncatedError(FreeProxyError): pass
class FilterValidationError(FreeProxyError): pass

def _now() -> datetime: return datetime.now(timezone.utc)
def _parse_time(value: Any) -> Optional[datetime]:
    if not isinstance(value, str) or len(value) < 20: return None
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
        return None if parsed.tzinfo is None else parsed.astimezone(timezone.utc)
    except ValueError: return None
def _iso_time(value: Any) -> Optional[str]:
    parsed = _parse_time(value)
    return None if not parsed else parsed.isoformat(timespec="milliseconds").replace("+00:00", "Z")
def _public_ipv4(ip: Any) -> bool:
    if not isinstance(ip, str): return False
    parts = ip.split(".")
    if len(parts) != 4 or any(not p.isdigit() or int(p) > 255 for p in parts): return False
    value = sum(part * 256 ** (3 - index) for index, part in enumerate(map(int, parts)))
    ranges = ((0x00000000, 8), (0x0a000000, 8), (0x64400000, 10), (0x7f000000, 8), (0xa9fe0000, 16), (0xac100000, 12), (0xc0000000, 24), (0xc0000200, 24), (0xc0a80000, 16), (0xc6120000, 15), (0xc6336400, 24), (0xcb007100, 24), (0xe0000000, 4), (0xf0000000, 4))
    return not any(value // 2 ** (32 - prefix) == network // 2 ** (32 - prefix) for network, prefix in ranges)
def _number(value: Any) -> Optional[float]: return None if value is None else float(value) if type(value) in (int, float) and math.isfinite(value) else None
def _copy(proxy: Proxy) -> Proxy: return Proxy(**proxy.__dict__)

def _validate_filters(filters: Optional[Dict[str, Any]]) -> Dict[str, Any]:
    values = asdict(filters) if isinstance(filters, Filters) else dict(filters or {})
    allowed = {"protocol", "country", "anonymity", "https", "max_latency_ms", "min_uptime_7d", "min_checks_7d", "checked_within_min", "limit"}
    unknown = set(values) - allowed
    if unknown: raise FilterValidationError("Unknown filter: %s" % sorted(unknown)[0])
    if values.get("protocol") is not None and values["protocol"] not in PROTOCOLS: raise FilterValidationError("protocol must be http, socks4, or socks5")
    if values.get("country") is not None and not re.match(r"^[a-zA-Z]{2}$", values["country"]): raise FilterValidationError("country must be a two-letter code")
    if values.get("anonymity") is not None and values["anonymity"] not in ANONYMITY: raise FilterValidationError("Invalid anonymity value")
    if values.get("https") is not None and not isinstance(values["https"], bool): raise FilterValidationError("https must be boolean")
    for key in ("max_latency_ms", "min_uptime_7d", "min_checks_7d", "limit"):
        if values.get(key) is not None and (type(values[key]) is not int or values[key] < 0): raise FilterValidationError("%s must be a non-negative integer" % key)
    values["checked_within_min"] = values.get("checked_within_min", 30)
    if type(values["checked_within_min"]) is not int or not 1 <= values["checked_within_min"] <= 1440: raise FilterValidationError("checked_within_min must be an integer from 1 to 1440")
    if values.get("country"): values["country"] = values["country"].lower()
    return values

def _map_row(row: Any, source: str) -> Proxy:
    if not isinstance(row, dict): raise SnapshotValidationError("Snapshot contains an invalid proxy row")
    def value(name: str) -> Any: return row.get(FIELD_BY_PY[name][source])
    protocol, ip, port = value("protocol"), value("ip"), value("port")
    first_seen, last_checked = value("first_seen"), value("last_checked")
    raw_asn = value("asn")
    try: asn = None if raw_asn is None else int(str(raw_asn).removeprefix("AS"))
    except ValueError: asn = -1
    country = value("country")
    api_latency, api_median_latency = value("latency_ms"), value("latency_median_ms")
    proxy = Proxy(protocol=protocol, ip=ip, port=port, url="%s://%s:%s" % (protocol, ip, port), country=country.lower() if isinstance(country, str) else country, region=value("region"), city=value("city"), timezone=value("timezone"), asn=asn, asn_org=value("asn_org"), anonymity=value("anonymity"), https=value("https"), latency_ms=math.floor(api_latency + .5) if source == "api" and _number(api_latency) is not None else api_latency, latency_median_ms=api_median_latency, uptime_24h=value("uptime_24h"), uptime_7d=value("uptime_7d"), checks_7d=value("checks_7d"), exit_ip=value("exit_ip"), sources_count=value("sources_count"), first_seen=_iso_time(first_seen), last_checked=_iso_time(last_checked))
    if proxy.protocol not in PROTOCOLS or not _public_ipv4(proxy.ip) or type(proxy.port) is not int or not 1 <= proxy.port <= 65535 or proxy.anonymity not in ANONYMITY or not proxy.first_seen or not proxy.last_checked: raise SnapshotValidationError("Snapshot contains an invalid proxy row")
    if proxy.country is not None and (not isinstance(proxy.country, str) or not re.match(r"^[a-z]{2}$", proxy.country)): raise SnapshotValidationError("Invalid country")
    if proxy.asn is not None and (type(proxy.asn) is not int or proxy.asn < 0): raise SnapshotValidationError("Invalid ASN")
    if proxy.https is not None and not isinstance(proxy.https, bool): raise SnapshotValidationError("Invalid https value")
    if any(not isinstance(getattr(proxy, key), str) and getattr(proxy, key) is not None for key in ("region", "city", "timezone", "asn_org", "exit_ip")): raise SnapshotValidationError("Invalid nullable string")
    if any(_number(getattr(proxy, key)) is None and getattr(proxy, key) is not None for key in ("latency_ms", "latency_median_ms", "uptime_24h", "uptime_7d")): raise SnapshotValidationError("Invalid nullable number")
    if type(proxy.checks_7d) is not int or proxy.checks_7d < 0 or type(proxy.sources_count) is not int or proxy.sources_count < 0: raise SnapshotValidationError("Invalid count")
    return Proxy(**{**proxy.__dict__, "uptime_7d": None if proxy.checks_7d < 50 else proxy.uptime_7d})

def _sort(rows: List[Proxy]) -> List[Proxy]:
    return sorted(rows, key=lambda p: (p.uptime_7d is None, -(p.uptime_7d or 0), p.latency_ms is None, p.latency_ms or 0, p.url))

class Client:
    def __init__(self, source: str = "api", api_url: str = DEFAULT_API_URL, github_url: str = DEFAULT_GITHUB_URL, transport: Optional[Callable[[str, Dict[str, str], float], Tuple[int, Dict[str, str], Any]]] = None, now: Callable[[], datetime] = _now, timeout: float = 10.0):
        if source not in ("api", "github"): raise FilterValidationError("source must be api or github")
        self.source, self.api_url, self.github_url, self.transport, self.now, self.timeout = source, api_url, github_url, transport or self._urllib_transport, now, timeout
        self.cache = None
    def _urllib_transport(self, url: str, headers: Dict[str, str], timeout: float):
        request = Request(url, headers=headers)
        try:
            with urlopen(request, timeout=timeout) as response: return response.status, dict(response.headers.items()), json.loads(response.read().decode("utf-8"))
        except HTTPError as error: return error.code, dict(error.headers.items()), None
        except socket.timeout as error: raise TimeoutError("Snapshot request timed out after %ss" % timeout) from error
        except URLError as error:
            if isinstance(error.reason, socket.timeout): raise TimeoutError("Snapshot request timed out after %ss" % timeout) from error
            raise FreeProxyError("Snapshot request failed: %s" % error.reason) from error
        except (UnicodeDecodeError, json.JSONDecodeError) as error: raise SnapshotValidationError("Malformed snapshot JSON") from error
    def _rows(self) -> List[Proxy]:
        now = self.now(); clock = monotonic()
        if self.cache and clock < self.cache["expires"]:
            self._validate_generated_at(self.cache["generated_at"], now)
            return self.cache["rows"]
        headers = {"If-None-Match": self.cache["etag"]} if self.cache and self.cache["etag"] else {}
        try: status, response_headers, body = self.transport(self.api_url if self.source == "api" else self.github_url, headers, self.timeout)
        except TimeoutError: raise
        except (socket.timeout, TimeoutError) as error: raise TimeoutError("Snapshot request timed out after %ss" % self.timeout) from error
        if status == 304:
            if not self.cache: raise NotModifiedWithoutCacheError("Received 304 without a cached snapshot")
            self._validate_generated_at(self.cache["generated_at"], now)
            self.cache["expires"] = clock + min(60, int(re.search(r"max-age=(\d+)", response_headers.get("Cache-Control", ""), re.I).group(1)) if re.search(r"max-age=(\d+)", response_headers.get("Cache-Control", ""), re.I) else 60)
            return self.cache["rows"]
        if status < 200 or status >= 300: raise HttpError(status)
        if self.source == "api":
            if not isinstance(body, dict) or not isinstance(body.get("proxies"), list): raise SnapshotValidationError("Malformed snapshot envelope")
            if body.get("truncated") is True: raise SnapshotTruncatedError("Snapshot is truncated")
            if type(body.get("count")) is not int or body["count"] != len(body["proxies"]) or (body.get("truncated") is not None and type(body["truncated"]) is not bool): raise SnapshotValidationError("Malformed snapshot envelope")
            self._validate_generated_at(body.get("generatedAt"), now)
            rows = [_map_row(row, "api") for row in body["proxies"]]
        else:
            if not isinstance(body, list): raise SnapshotValidationError("Malformed GitHub proxy list")
            rows = [_map_row(row, "github") for row in body]
        cache_control = response_headers.get("Cache-Control", response_headers.get("cache-control", "")); match = re.search(r"max-age=(\d+)", cache_control, re.I)
        self.cache = {"rows": rows, "etag": response_headers.get("ETag", response_headers.get("etag")), "generated_at": body.get("generatedAt") if self.source == "api" else None, "expires": clock + min(60, int(match.group(1)) if match else 60)}
        return rows
    def _validate_generated_at(self, value: Any, now: datetime) -> None:
        if self.source != "api": return
        generated = _parse_time(value)
        if not generated or generated > now + timedelta(seconds=5) or (now - generated).total_seconds() > 120: raise SnapshotValidationError("Snapshot generatedAt is outside the accepted window")
    def get_proxies(self, filters: Optional[Dict[str, Any]] = None) -> List[Proxy]:
        values = _validate_filters(filters); rows_snapshot = self._rows(); now_timestamp = self.now().timestamp(); cutoff = now_timestamp - values["checked_within_min"] * 60
        rows = [p for p in rows_snapshot if cutoff <= _parse_time(p.last_checked).timestamp() <= now_timestamp + 5]
        for field in ("protocol", "country", "anonymity", "https"):
            if field in values and values[field] is not None: rows = [p for p in rows if getattr(p, field) == values[field]]
        if values.get("max_latency_ms") is not None: rows = [p for p in rows if p.latency_ms is not None and p.latency_ms <= values["max_latency_ms"]]
        if values.get("min_uptime_7d") is not None: rows = [p for p in rows if p.uptime_7d is not None and p.uptime_7d >= values["min_uptime_7d"]]
        if values.get("min_checks_7d") is not None: rows = [p for p in rows if p.checks_7d >= values["min_checks_7d"]]
        return [_copy(p) for p in _sort(rows)[:values.get("limit")]]
    def pick_best(self, n: int, filters: Optional[Dict[str, Any]] = None) -> List[Proxy]:
        if type(n) is not int or n < 0: raise FilterValidationError("n must be a non-negative integer")
        return self.get_proxies(filters)[:n]
    def rotate(self, filters: Optional[Dict[str, Any]] = None) -> Iterator[Proxy]:
        values = _validate_filters(filters); rows = self.get_proxies(values); index = 0
        while rows:
            cutoff = self.now().timestamp() - values["checked_within_min"] * 60
            row = rows[index % len(rows)]; index += 1
            if cutoff <= _parse_time(row.last_checked).timestamp() <= self.now().timestamp() + 5: yield _copy(row)
            else: rows.remove(row)

def to_proxy_url(proxy: Proxy) -> str: return "%s://%s:%s" % (proxy.protocol, proxy.ip, proxy.port)
def to_requests_proxies(proxy: Proxy) -> Dict[str, str]: return {"http": to_proxy_url(proxy), "https": to_proxy_url(proxy)}
def to_httpx_proxy(proxy: Proxy) -> str: return to_proxy_url(proxy)
_default_client = Client()
def get_proxies(filters: Optional[Dict[str, Any]] = None) -> List[Proxy]: return _default_client.get_proxies(filters)
def pick_best(n: int, filters: Optional[Dict[str, Any]] = None) -> List[Proxy]: return _default_client.pick_best(n, filters)
def rotate(filters: Optional[Dict[str, Any]] = None) -> Iterator[Proxy]: return _default_client.rotate(filters)
