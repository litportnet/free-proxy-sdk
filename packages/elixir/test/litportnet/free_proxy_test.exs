defmodule Litportnet.FreeProxyTest do
  use ExUnit.Case, async: true

  alias Litportnet.FreeProxy
  alias Litportnet.FreeProxy.Client
  alias Litportnet.FreeProxy.Error

  # Fixed "now" the fixture's timestamps are relative to. All `pingAt` values
  # in the fixture sit in the 20-30 minutes before this instant, and
  # `generatedAt` is exactly this instant.
  @now ~U[2026-09-10 00:00:00Z]

  defp fixture do
    [__DIR__, "..", "fixtures", "api_snapshot.json"]
    |> Path.join()
    |> File.read!()
    |> Jason.decode!()
  end

  defp client_with_response(status, body) do
    {:ok, client} =
      FreeProxy.new(now: fn -> @now end, transport: fn _url, _timeout -> {:ok, status, [], body} end)

    client
  end

  defp client_with_transport(transport) do
    {:ok, client} = FreeProxy.new(now: fn -> @now end, transport: transport)
    client
  end

  defp default_client, do: client_with_response(200, fixture())

  describe "get_proxies/2" do
    test "normalizes fields and returns every fresh row by default" do
      {:ok, proxies} = FreeProxy.get_proxies(default_client())
      assert length(proxies) == 6

      first = Enum.find(proxies, &(&1.ip == "8.8.8.8"))
      assert first.url == "http://8.8.8.8:8080"
      assert first.protocol == "http"
      assert first.port == 8080
      assert first.country == "us"
      assert first.asn == 15_169
      assert first.https == true
      assert first.latency_ms == 120
      assert is_float(first.latency_median_ms)
      assert first.uptime_7d == 98.2

      au = Enum.find(proxies, &(&1.ip == "1.1.1.1"))
      assert au.asn == 13_335
      assert au.city == nil
      assert au.https == nil
      assert au.checks_7d == 10
      assert au.uptime_7d == nil

      de = Enum.find(proxies, &(&1.ip == "9.9.9.9"))
      assert de.latency_ms == nil
    end

    test "sorts by seven-day uptime desc, then latency asc, then url, with nil-uptime rows last" do
      {:ok, proxies} = FreeProxy.get_proxies(default_client())

      assert Enum.map(proxies, & &1.ip) == [
               "8.8.8.8",
               "208.67.222.222",
               "185.228.168.9",
               "76.76.19.19",
               "9.9.9.9",
               "1.1.1.1"
             ]
    end

    test "nulls uptime_7d whenever checks_7d is below 50, even if the raw value is high" do
      body = put_in(fixture(), ["proxies", Access.at(1), "uptime7d"], 99.9)
      {:ok, proxies} = FreeProxy.get_proxies(client_with_response(200, body))

      au = Enum.find(proxies, &(&1.ip == "1.1.1.1"))
      assert au.checks_7d == 10
      assert au.uptime_7d == nil
    end

    test "filters by protocol" do
      {:ok, proxies} = FreeProxy.get_proxies(default_client(), protocol: "socks5")
      assert Enum.map(proxies, & &1.ip) == ["185.228.168.9", "1.1.1.1"]
    end

    test "filters by country, case-insensitively, and stores it downcased" do
      {:ok, proxies} = FreeProxy.get_proxies(default_client(), country: "US")
      assert Enum.map(proxies, & &1.ip) == ["8.8.8.8", "185.228.168.9"]
      assert Enum.all?(proxies, &(&1.country == "us"))
    end

    test "filters by anonymity" do
      {:ok, proxies} = FreeProxy.get_proxies(default_client(), anonymity: "elite")
      assert Enum.map(proxies, & &1.ip) == ["8.8.8.8", "208.67.222.222"]
    end

    test "filters by https" do
      {:ok, proxies} = FreeProxy.get_proxies(default_client(), https: false)
      assert Enum.map(proxies, & &1.ip) == ["76.76.19.19", "9.9.9.9"]
    end

    test "filters by max_latency_ms, excluding proxies with unknown latency" do
      {:ok, proxies} = FreeProxy.get_proxies(default_client(), max_latency_ms: 150)
      assert Enum.map(proxies, & &1.ip) == ["8.8.8.8", "208.67.222.222"]
    end

    test "filters by min_uptime_7d, excluding proxies with nulled uptime" do
      {:ok, proxies} = FreeProxy.get_proxies(default_client(), min_uptime_7d: 90)
      assert Enum.map(proxies, & &1.ip) == ["8.8.8.8", "208.67.222.222", "185.228.168.9"]
    end

    test "filters by min_checks_7d" do
      {:ok, proxies} = FreeProxy.get_proxies(default_client(), min_checks_7d: 60)
      assert Enum.map(proxies, & &1.ip) == ["8.8.8.8", "185.228.168.9", "76.76.19.19", "9.9.9.9"]
    end

    test "applies limit, including a limit of zero" do
      {:ok, proxies} = FreeProxy.get_proxies(default_client(), limit: 2)
      assert Enum.map(proxies, & &1.ip) == ["8.8.8.8", "208.67.222.222"]

      {:ok, proxies} = FreeProxy.get_proxies(default_client(), limit: 0)
      assert proxies == []
    end

    test "filters by checked_within_min, inclusive of the lower boundary" do
      {:ok, proxies} = FreeProxy.get_proxies(default_client(), checked_within_min: 15)
      assert Enum.map(proxies, & &1.ip) == ["8.8.8.8", "208.67.222.222", "9.9.9.9", "1.1.1.1"]
    end

    test "excludes rows whose pingAt has fallen outside the default freshness window" do
      body = put_in(fixture(), ["proxies", Access.at(0), "pingAt"], "2026-09-09T23:29:59Z")
      {:ok, proxies} = FreeProxy.get_proxies(client_with_response(200, body))

      refute Enum.any?(proxies, &(&1.ip == "8.8.8.8"))
      assert length(proxies) == 5
    end

    test "rejects a non-keyword-list filters argument" do
      assert {:error, %Error{type: :filter_validation}} =
               FreeProxy.get_proxies(default_client(), [1, 2, 3])
    end

    test "rejects invalid filter options" do
      invalid_filters = [
        [https: "yes"],
        [protocol: false],
        [checked_within_min: false],
        [limit: -1],
        [unknown: 1],
        [country: "usa"],
        [anonymity: "invisible"],
        [max_latency_ms: -1],
        [min_uptime_7d: -1],
        [min_checks_7d: -1],
        [checked_within_min: 0],
        [checked_within_min: 1441]
      ]

      Enum.each(invalid_filters, fn filters ->
        assert {:error, %Error{type: :filter_validation}} =
                 FreeProxy.get_proxies(default_client(), filters),
               "expected #{inspect(filters)} to be rejected"
      end)
    end
  end

  describe "snapshot envelope and row validation" do
    test "returns an :http error carrying the status for non-2xx responses" do
      assert {:error, %Error{type: :http, status: 500}} =
               FreeProxy.get_proxies(client_with_response(500, %{}))

      assert {:error, %Error{type: :http, status: 429}} =
               FreeProxy.get_proxies(client_with_response(429, []))
    end

    test "returns a :snapshot_truncated error when the snapshot reports truncated: true" do
      body = %{
        "generatedAt" => "2026-09-10T00:00:00.000Z",
        "count" => 0,
        "truncated" => true,
        "proxies" => []
      }

      assert {:error, %Error{type: :snapshot_truncated}} =
               FreeProxy.get_proxies(client_with_response(200, body))
    end

    test "returns a :snapshot_validation error when count does not match the row count" do
      body = Map.put(fixture(), "count", 99)

      assert {:error, %Error{type: :snapshot_validation}} =
               FreeProxy.get_proxies(client_with_response(200, body))
    end

    test "returns a :snapshot_validation error when generatedAt is outside the accepted window" do
      stale = Map.put(fixture(), "generatedAt", "2026-09-09T23:57:59Z")

      assert {:error, %Error{type: :snapshot_validation}} =
               FreeProxy.get_proxies(client_with_response(200, stale))

      future = Map.put(fixture(), "generatedAt", "2026-09-10T00:00:06Z")

      assert {:error, %Error{type: :snapshot_validation}} =
               FreeProxy.get_proxies(client_with_response(200, future))
    end

    test "returns a :snapshot_validation error for malformed JSON bodies" do
      assert {:error, %Error{type: :snapshot_validation}} =
               FreeProxy.get_proxies(client_with_response(200, "{not valid json"))
    end

    test "rejects rows whose host is not a public IPv4 address" do
      body = put_in(fixture(), ["proxies", Access.at(0), "host"], "127.0.0.1")

      assert {:error, %Error{type: :snapshot_validation}} =
               FreeProxy.get_proxies(client_with_response(200, body))
    end

    test "rejects rows with malformed individual fields" do
      cases = [
        {["proxies", Access.at(0), "host"], nil},
        {["proxies", Access.at(0), "port"], "8080"},
        {["proxies", Access.at(0), "asn"], true},
        {["proxies", Access.at(0), "geoCountry"], 123},
        {["proxies", Access.at(0), "responseTimeMs"], "not-a-number"},
        {["proxies", Access.at(0), "anonymity"], "super-secret"},
        {["proxies", Access.at(0), "pingAt"], "2026-09-10T00:00:00"},
        {["proxies", Access.at(0), "createdAt"], "2026-02-30T00:00:00Z"}
      ]

      Enum.each(cases, fn {path, value} ->
        body = put_in(fixture(), path, value)

        assert {:error, %Error{type: :snapshot_validation}} =
                 FreeProxy.get_proxies(client_with_response(200, body)),
               "expected #{inspect(path)} = #{inspect(value)} to be rejected"
      end)
    end
  end

  describe "transport" do
    test "propagates a transport timeout as a :timeout error and forwards the configured timeout" do
      test_pid = self()

      client =
        client_with_transport(fn _url, timeout ->
          send(test_pid, {:timeout_seen, timeout})
          {:error, :timeout}
        end)

      assert {:error, %Error{type: :timeout}} = FreeProxy.get_proxies(client)
      assert_received {:timeout_seen, 10_000}
    end

    test "maps other transport errors to a :transport error" do
      client = client_with_transport(fn _url, _timeout -> {:error, :nxdomain} end)
      assert {:error, %Error{type: :transport}} = FreeProxy.get_proxies(client)
    end
  end

  describe "pick_best/3" do
    test "returns the top N proxies after filtering and sorting" do
      {:ok, proxies} = FreeProxy.pick_best(default_client(), 2)
      assert Enum.map(proxies, & &1.ip) == ["8.8.8.8", "208.67.222.222"]

      {:ok, proxies} = FreeProxy.pick_best(default_client(), 10, protocol: "socks4")
      assert Enum.map(proxies, & &1.ip) == ["76.76.19.19", "9.9.9.9"]
    end

    test "rejects a negative count" do
      assert {:error, %Error{type: :filter_validation}} =
               FreeProxy.pick_best(default_client(), -1)
    end
  end

  describe "bang variants" do
    test "get_proxies!/2 and pick_best!/3 return the list directly" do
      proxies = FreeProxy.get_proxies!(default_client())
      assert length(proxies) == 6

      best = FreeProxy.pick_best!(default_client(), 1)
      assert Enum.map(best, & &1.ip) == ["8.8.8.8"]
    end

    test "get_proxies!/2 raises Litportnet.FreeProxy.Error on failure" do
      assert_raise Error, ~r/HTTP 500/, fn ->
        FreeProxy.get_proxies!(client_with_response(500, %{}))
      end
    end

    test "pick_best!/3 raises Litportnet.FreeProxy.Error on failure" do
      assert_raise Error, fn -> FreeProxy.pick_best!(default_client(), -1) end
    end
  end

  describe "new/1" do
    test "builds a client with defaults" do
      assert {:ok, %Client{timeout: 10_000}} = FreeProxy.new()
    end

    test "rejects invalid options" do
      assert {:error, %Error{type: :filter_validation}} = FreeProxy.new(timeout: 0)
      assert {:error, %Error{type: :filter_validation}} = FreeProxy.new(timeout: -5)
      assert {:error, %Error{type: :filter_validation}} = FreeProxy.new(timeout: "10000")
      assert {:error, %Error{type: :filter_validation}} = FreeProxy.new(api_url: :not_a_string)
      assert {:error, %Error{type: :filter_validation}} = FreeProxy.new(transport: fn _one -> :ok end)
      assert {:error, %Error{type: :filter_validation}} = FreeProxy.new(now: fn _one -> :ok end)
      assert {:error, %Error{type: :filter_validation}} = FreeProxy.new([1, 2, 3])
    end
  end
end
