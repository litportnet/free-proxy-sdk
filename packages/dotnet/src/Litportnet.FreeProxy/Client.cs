using System.Globalization;
using System.Net;
using System.Net.Http;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace Litportnet.FreeProxy;

public sealed record Proxy(string Protocol, string Ip, int Port, string Url, string? Country, string? Region, string? City, string? Timezone, long? Asn, string? AsnOrg, string Anonymity, bool? Https, double? LatencyMs, double? LatencyMedianMs, double? Uptime24h, double? Uptime7d, int Checks7d, string? ExitIp, int SourcesCount, string FirstSeen, string LastChecked);
public sealed record Filters(string? Protocol = null, string? Country = null, string? Anonymity = null, bool? Https = null, int? MaxLatencyMs = null, int? MinUptime7d = null, int? MinChecks7d = null, int CheckedWithinMin = 30, int? Limit = null);
public class FreeProxyException(string message) : Exception(message);
public sealed class TimeoutException(string message) : FreeProxyException(message);
public sealed class HttpException(int status) : FreeProxyException($"Snapshot request failed with HTTP {status}") { public int Status { get; } = status; }
public sealed class SnapshotValidationException(string message) : FreeProxyException(message);
public sealed class SnapshotTruncatedException() : FreeProxyException("Snapshot is truncated");
public sealed class FilterValidationException(string message) : FreeProxyException(message);

/// <summary>Asynchronous, standard-library client for the documented Litport API snapshot.</summary>
public sealed class Client : IDisposable
{
    public const string DefaultApiUrl = "https://litport.net/api/free-proxy/snapshot?checkedWithinMin=1440";
    private readonly HttpClient http; private readonly TimeProvider clock; private readonly bool disposeHttp;
    public TimeSpan Timeout { get; }
    public Client(HttpMessageHandler? handler = null, string apiUrl = DefaultApiUrl, TimeSpan? timeout = null, TimeProvider? timeProvider = null)
    {
        Timeout = timeout ?? TimeSpan.FromSeconds(10); if (Timeout <= TimeSpan.Zero) throw new FilterValidationException("timeout must be positive");
        http = handler is null ? new HttpClient() : new HttpClient(handler, true); http.Timeout = System.Threading.Timeout.InfiniteTimeSpan; http.BaseAddress = new Uri(apiUrl); disposeHttp = true; clock = timeProvider ?? TimeProvider.System;
    }
    public async Task<IReadOnlyList<Proxy>> GetProxiesAsync(Filters? input = null, CancellationToken cancellationToken = default)
    {
        var f = ValidateFilters(input ?? new Filters()); using var timeout = new CancellationTokenSource(Timeout); using var linked = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken, timeout.Token);
        HttpResponseMessage response;
        try { response = await http.GetAsync("", linked.Token).ConfigureAwait(false); }
        catch (OperationCanceledException) when (timeout.IsCancellationRequested && !cancellationToken.IsCancellationRequested) { throw new TimeoutException($"Snapshot request timed out after {Timeout.TotalSeconds:0.###}s"); }
        catch (HttpRequestException ex) { throw new FreeProxyException("Snapshot request failed: " + ex.Message); }
        using (response) {
            if (!response.IsSuccessStatusCode) throw new HttpException((int)response.StatusCode);
            JsonDocument document;
            try { document = JsonDocument.Parse(await response.Content.ReadAsStreamAsync(linked.Token).ConfigureAwait(false)); }
            catch (JsonException) { throw new SnapshotValidationException("Malformed snapshot JSON"); }
            using (document) {
                var root = document.RootElement;
                if (root.ValueKind != JsonValueKind.Object || !root.TryGetProperty("proxies", out var records) || records.ValueKind != JsonValueKind.Array) throw new SnapshotValidationException("Malformed snapshot envelope");
                if (root.TryGetProperty("truncated", out var truncated) && truncated.ValueKind == JsonValueKind.True) throw new SnapshotTruncatedException();
                if (!root.TryGetProperty("count", out var count) || count.ValueKind != JsonValueKind.Number || !count.TryGetInt32(out var recordCount) || recordCount != records.GetArrayLength() || (root.TryGetProperty("truncated", out truncated) && truncated.ValueKind is not JsonValueKind.True and not JsonValueKind.False)) throw new SnapshotValidationException("Malformed snapshot envelope");
                ValidateGeneratedAt(Value(root, "generatedAt"));
                var now = clock.GetUtcNow(); var cutoff = now.AddMinutes(-f.CheckedWithinMin); var rows = new List<Proxy>();
                foreach (var record in records.EnumerateArray()) { var row = Map(record); var checkedAt = ParseTime(row.LastChecked); if (checkedAt >= cutoff && checkedAt <= now.AddSeconds(5) && Matches(row, f)) rows.Add(row); }
                return rows.OrderBy(x => x.Uptime7d is null).ThenByDescending(x => x.Uptime7d).ThenBy(x => x.LatencyMs is null).ThenBy(x => x.LatencyMs).ThenBy(x => x.Url, StringComparer.Ordinal).Take(f.Limit ?? int.MaxValue).ToList();
            }
        }
    }
    public async Task<IReadOnlyList<Proxy>> PickBestAsync(int count, Filters? filters = null, CancellationToken cancellationToken = default) { if (count < 0) throw new FilterValidationException("count must be a non-negative integer"); return (await GetProxiesAsync(filters, cancellationToken).ConfigureAwait(false)).Take(count).ToList(); }
    public static string ToProxyUrl(Proxy proxy) => $"{proxy.Protocol}://{proxy.Ip}:{proxy.Port}";
    public void Dispose() { if (disposeHttp) http.Dispose(); }

    private static Filters ValidateFilters(Filters f) {
        if (f.Protocol is not null && f.Protocol is not ("http" or "socks4" or "socks5")) throw new FilterValidationException("protocol must be http, socks4, or socks5");
        if (f.Country is not null && !Regex.IsMatch(f.Country, "^[a-zA-Z]{2}$")) throw new FilterValidationException("country must be a two-letter code");
        if (f.Anonymity is not null && f.Anonymity is not ("transparent" or "anonymous" or "elite" or "unknown")) throw new FilterValidationException("Invalid anonymity value");
        if (f.MaxLatencyMs < 0 || f.MinUptime7d < 0 || f.MinChecks7d < 0 || f.Limit < 0) throw new FilterValidationException("numeric filters must be non-negative");
        if (f.CheckedWithinMin is < 1 or > 1440) throw new FilterValidationException("checkedWithinMin must be from 1 to 1440");
        return f with { Country = f.Country?.ToLowerInvariant() };
    }
    private void ValidateGeneratedAt(string? raw) { var time = ParseTime(raw); var now = clock.GetUtcNow(); if (time < now.AddMinutes(-2) || time > now.AddSeconds(5)) throw new SnapshotValidationException("Snapshot generatedAt is outside the accepted window"); }
    private static bool Matches(Proxy p, Filters f) => (f.Protocol is null || p.Protocol == f.Protocol) && (f.Country is null || p.Country == f.Country) && (f.Anonymity is null || p.Anonymity == f.Anonymity) && (f.Https is null || p.Https == f.Https) && (f.MaxLatencyMs is null || p.LatencyMs is not null && p.LatencyMs <= f.MaxLatencyMs) && (f.MinUptime7d is null || p.Uptime7d is not null && p.Uptime7d >= f.MinUptime7d) && (f.MinChecks7d is null || p.Checks7d >= f.MinChecks7d);
    private static Proxy Map(JsonElement r) {
        if (r.ValueKind != JsonValueKind.Object) throw new SnapshotValidationException("Snapshot contains an invalid proxy row"); var protocol = Value(r,"protocol"); var ip = Value(r,"host"); var port = Int(r,"port"); var anonymity = Value(r,"anonymity");
        if (protocol is not ("http" or "socks4" or "socks5") || !PublicIpv4(ip) || port is < 1 or > 65535 || anonymity is not ("transparent" or "anonymous" or "elite" or "unknown")) throw new SnapshotValidationException("Snapshot contains an invalid proxy row");
        var country = NullableString(r,"geoCountry"); if (country is not null && !Regex.IsMatch(country,"^[a-zA-Z]{2}$")) throw new SnapshotValidationException("Invalid country"); var asnRaw = AsnValue(r); long? asn = asnRaw is null ? null : asnRaw.StartsWith("AS", StringComparison.Ordinal) && long.TryParse(asnRaw[2..], out var parsedAsn) ? parsedAsn : long.TryParse(asnRaw, out parsedAsn) ? parsedAsn : null; if (asnRaw is not null && (asn is null || asn < 0)) throw new SnapshotValidationException("Invalid ASN");
        var https = NullableBool(r,"https"); var checks = Int(r,"checks7d"); var sources = Int(r,"sourcesCount"); if (checks < 0 || sources < 0) throw new SnapshotValidationException("Invalid count"); var first = Iso(Value(r,"createdAt")); var last = Iso(Value(r,"pingAt"));
        var uptime7d = Number(r,"uptime7d");
        return new Proxy(protocol!, ip!, port, $"{protocol}://{ip}:{port}", country?.ToLowerInvariant(), NullableString(r,"geoRegion"), NullableString(r,"geoCity"), NullableString(r,"geoTimezone"), asn, NullableString(r,"asnOrgName"), anonymity!, https, Number(r,"responseTimeMs", true), Number(r,"responseTimeMedianMs"), Number(r,"uptime24h"), checks < 50 ? null : uptime7d, checks, NullableString(r,"externalIp"), sources, first, last);
    }
    private static string? Value(JsonElement e,string name) => e.TryGetProperty(name,out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() : e.TryGetProperty(name,out v) && v.ValueKind == JsonValueKind.Null ? null : e.TryGetProperty(name,out v) && v.ValueKind == JsonValueKind.Number ? v.GetRawText() : null;
    private static string? NullableString(JsonElement e,string n) { if (!e.TryGetProperty(n,out var v) || v.ValueKind == JsonValueKind.Null) return null; return v.ValueKind == JsonValueKind.String ? v.GetString() : throw new SnapshotValidationException("Invalid nullable string"); }
    private static string? AsnValue(JsonElement e) { if (!e.TryGetProperty("asn", out var v) || v.ValueKind == JsonValueKind.Null) return null; return v.ValueKind is JsonValueKind.String or JsonValueKind.Number ? (v.ValueKind == JsonValueKind.String ? v.GetString() : v.GetRawText()) : throw new SnapshotValidationException("Invalid ASN"); }
    private static bool? NullableBool(JsonElement e,string n) { if (!e.TryGetProperty(n,out var v) || v.ValueKind == JsonValueKind.Null) return null; return v.ValueKind is JsonValueKind.True ? true : v.ValueKind is JsonValueKind.False ? false : throw new SnapshotValidationException("Invalid https value"); }
    private static int Int(JsonElement e,string n) => e.TryGetProperty(n,out var v) && v.ValueKind == JsonValueKind.Number && v.TryGetInt32(out var result) ? result : throw new SnapshotValidationException("Invalid count");
    private static double? Number(JsonElement e,string n,bool round = false) { if (!e.TryGetProperty(n,out var v) || v.ValueKind == JsonValueKind.Null) return null; if (v.ValueKind != JsonValueKind.Number || !v.TryGetDouble(out var result) || !double.IsFinite(result)) throw new SnapshotValidationException("Invalid nullable number"); return round ? Math.Round(result, MidpointRounding.AwayFromZero) : result; }
    private static DateTimeOffset ParseTime(string? raw) { if (raw is null || !Regex.IsMatch(raw,"^\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}(?:\\.\\d+)?(?:Z|[+-]\\d{2}:\\d{2})$") || !DateTimeOffset.TryParse(raw, CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind, out var value)) throw new SnapshotValidationException("Invalid timestamp"); return value.ToUniversalTime(); }
    private static string Iso(string? raw) => ParseTime(raw).ToString("yyyy-MM-dd'T'HH:mm:ss.fff'Z'", CultureInfo.InvariantCulture);
    private static bool PublicIpv4(string? raw) { if (raw is null || !Regex.IsMatch(raw, "^\\d{1,3}(?:\\.\\d{1,3}){3}$") || !IPAddress.TryParse(raw, out var address) || address.AddressFamily != System.Net.Sockets.AddressFamily.InterNetwork || address.ToString() != raw) return false; var bytes = address.GetAddressBytes(); foreach (var (network,bits) in new[] { (new byte[]{0,0,0,0},8),(new byte[]{10,0,0,0},8),(new byte[]{100,64,0,0},10),(new byte[]{127,0,0,0},8),(new byte[]{169,254,0,0},16),(new byte[]{172,16,0,0},12),(new byte[]{192,0,0,0},24),(new byte[]{192,0,2,0},24),(new byte[]{192,168,0,0},16),(new byte[]{198,18,0,0},15),(new byte[]{198,51,100,0},24),(new byte[]{203,0,113,0},24),(new byte[]{224,0,0,0},4),(new byte[]{240,0,0,0},4) }) { var whole=bits/8; var remaining=bits%8; if (bytes.Take(whole).SequenceEqual(network.Take(whole)) && (remaining==0 || (bytes[whole] & (0xff << (8-remaining))) == (network[whole] & (0xff << (8-remaining))))) return false; } return true; }
}
