using System.Net;
using System.Text.Json;
using Litportnet.FreeProxy;

var fixture = await File.ReadAllTextAsync(Path.Combine(AppContext.BaseDirectory, "Fixtures", "api-snapshot.json"));
var time = new FixedTimeProvider(new DateTimeOffset(2026, 9, 10, 0, 0, 0, TimeSpan.Zero));
using var client = new Client(new StubHandler(_ => new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent(fixture) }), timeProvider: time);
var rows = await client.GetProxiesAsync();
Assert(rows.Count == 2 && rows[0].Url == "http://8.8.8.8:8080", "normalizes fixture");
Assert(rows[0].LatencyMs == 120 && rows[0].Asn == 15169 && rows[1].Uptime7d is null, "normalizes rounded latency, ASN, and nullable uptime");
Assert((await client.GetProxiesAsync(new Filters(Protocol: "socks5"))).Count == 1, "filters protocol");
Assert((await client.GetProxiesAsync(new Filters(MinUptime7d: 90))).Count == 1, "filters nullable uptime");
Assert((await client.GetProxiesAsync(new Filters(Limit: 0))).Count == 0, "permits zero limit");
await Throws<HttpException>(() => new Client(new StubHandler(_ => new HttpResponseMessage(HttpStatusCode.TooManyRequests)), timeProvider: time).GetProxiesAsync());
await Throws<SnapshotTruncatedException>(() => Api(new { generatedAt = "2026-09-10T00:00:00Z", count = 0, truncated = true, proxies = Array.Empty<object>() }).GetProxiesAsync());
await Throws<SnapshotValidationException>(() => Api(new { generatedAt = "2026-09-09T23:57:00Z", count = 0, proxies = Array.Empty<object>() }).GetProxiesAsync());
await Throws<SnapshotValidationException>(() => Api(new { generatedAt = "2026-09-10T00:00:00Z", count = 1, proxies = Array.Empty<object>() }).GetProxiesAsync());
await Throws<SnapshotValidationException>(() => ApiJson(fixture.Replace("\"host\":\"8.8.8.8\"", "\"host\":\"127.0.0.1\"", StringComparison.Ordinal)).GetProxiesAsync());
await Throws<SnapshotValidationException>(() => ApiJson(fixture.Replace("\"asn\":\"AS15169\"", "\"asn\":false", StringComparison.Ordinal)).GetProxiesAsync());
await Throws<SnapshotValidationException>(() => ApiJson(fixture.Replace("\"uptime7d\":55", "\"uptime7d\":\"bad\"", StringComparison.Ordinal)).GetProxiesAsync());
await Throws<SnapshotValidationException>(() => ApiJson(fixture.Replace("2026-09-09T23:50:00.000Z", "2026-09-09T23:50:00", StringComparison.Ordinal)).GetProxiesAsync());
using (var timeoutClient = new Client(new SlowHandler(), timeout: TimeSpan.FromMilliseconds(10), timeProvider: time)) await Throws<Litportnet.FreeProxy.TimeoutException>(() => timeoutClient.GetProxiesAsync());
Console.WriteLine(".NET SDK tests passed");

Client Api(object body) => new(new StubHandler(_ => new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent(JsonSerializer.Serialize(body)) }), timeProvider: time);
Client ApiJson(string body) => new(new StubHandler(_ => new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent(body) }), timeProvider: time);
static void Assert(bool condition, string message) { if (!condition) throw new Exception("Assertion failed: " + message); }
static async Task Throws<T>(Func<Task> action) where T : Exception { try { await action(); } catch (T) { return; } throw new Exception($"Expected {typeof(T).Name}"); }
sealed class FixedTimeProvider(DateTimeOffset value) : TimeProvider { public override DateTimeOffset GetUtcNow() => value; }
sealed class StubHandler(Func<HttpRequestMessage, HttpResponseMessage> responder) : HttpMessageHandler { protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) => Task.FromResult(responder(request)); }
sealed class SlowHandler : HttpMessageHandler { protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) { await Task.Delay(Timeout.InfiniteTimeSpan, token); return new HttpResponseMessage(); } }
