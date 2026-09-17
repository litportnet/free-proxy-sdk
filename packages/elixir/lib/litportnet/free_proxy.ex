defmodule Litportnet.FreeProxy do
  @moduledoc """
  Elixir client for [Litport](https://litport.net/free-proxy)'s public
  snapshot of verified free HTTP, SOCKS4, and SOCKS5 proxies.

  The snapshot endpoint requires no API key. See the
  [API documentation](https://litport.net/docs/free-proxy-api) for the shape
  of the underlying HTTP response.

  This client only retrieves proxy records - it does not open connections
  through them, and it does not route any of your application's traffic.
  Free proxies are for testing only. Never route credentials, cookies,
  payment data, or private data through them.

  ## Usage

      {:ok, client} = Litportnet.FreeProxy.new()

      {:ok, proxies} =
        Litportnet.FreeProxy.get_proxies(client,
          protocol: "socks5",
          country: "us",
          max_latency_ms: 500,
          min_uptime_7d: 90,
          min_checks_7d: 50,
          checked_within_min: 30
        )

      Enum.each(proxies, &IO.puts(&1.url))

      {:ok, best} = Litportnet.FreeProxy.pick_best(client, 5, protocol: "http")

  ## Filters

  `get_proxies/2` and `pick_best/3` take the same keyword list of optional
  filters:

  | Key | Type | Description |
  | --- | --- | --- |
  | `:protocol` | string | `"http"`, `"socks4"`, or `"socks5"` |
  | `:country` | string | Two-letter country code (case-insensitive) |
  | `:anonymity` | string | `"transparent"`, `"anonymous"`, `"elite"`, or `"unknown"` |
  | `:https` | boolean | Require (`true`) or exclude (`false`) HTTPS support |
  | `:max_latency_ms` | non-negative integer | Maximum latency, in milliseconds |
  | `:min_uptime_7d` | non-negative integer | Minimum seven-day uptime percentage |
  | `:min_checks_7d` | non-negative integer | Minimum number of checks in the last seven days |
  | `:checked_within_min` | integer, `1..1440` | Only proxies checked this recently, in minutes (default `30`) |
  | `:limit` | non-negative integer | Maximum number of records to return |

  Results are sorted by seven-day uptime (descending, proxies with a known
  uptime first), then by latency (ascending, proxies with a known latency
  first), then by URL. `uptime_7d` is always `nil` for proxies with fewer
  than 50 checks in the last seven days, regardless of what the snapshot
  reports.

  The snapshot envelope itself is validated on every call: `count` must match
  the number of returned rows, `truncated` (if present) must be `false`, and
  `generatedAt` must fall within the two minutes before, or five seconds
  after, the current time. Every row's `host` must be a public IPv4 address.
  """

  alias Litportnet.FreeProxy.Client
  alias Litportnet.FreeProxy.Error
  alias Litportnet.FreeProxy.Proxy

  @known_filter_keys ~w(
    protocol country anonymity https max_latency_ms min_uptime_7d
    min_checks_7d limit checked_within_min
  )a

  @typedoc "The optional filters accepted by `get_proxies/2` and `pick_best/3`."
  @type filters :: keyword()

  @doc """
  Builds a new client. See `Litportnet.FreeProxy.Client.new/1` for the
  accepted options and their defaults.
  """
  @spec new(keyword()) :: {:ok, Client.t()} | {:error, Error.t()}
  def new(opts \\ []), do: Client.new(opts)

  @doc """
  Fetches the current snapshot and returns the proxies matching `filters`,
  normalized, freshness-checked, and sorted.

  Returns `{:error, %Litportnet.FreeProxy.Error{}}` if `filters` are invalid,
  the request fails or times out, the response is not a 2xx, or the snapshot
  fails validation. See the module documentation for the filter table and the
  `t:Litportnet.FreeProxy.Error.error_type/0` typedoc for the possible error
  types.
  """
  @spec get_proxies(Client.t(), filters()) :: {:ok, [Proxy.t()]} | {:error, Error.t()}
  def get_proxies(%Client{} = client, filters \\ []) do
    with {:ok, validated_filters} <- validate_filters(filters),
         {:ok, status, _headers, body} <- fetch(client),
         :ok <- validate_status(status),
         {:ok, snapshot} <- decode_body(body),
         now = client.now.(),
         {:ok, raw_proxies} <- validate_envelope(snapshot, now),
         {:ok, proxies} <- map_rows(raw_proxies) do
      filtered =
        proxies
        |> Enum.filter(&fresh_and_matches?(&1, validated_filters, now))
        |> sort_and_limit(validated_filters.limit)

      {:ok, filtered}
    else
      {:error, :timeout} ->
        {:error, Error.new(:timeout, "Snapshot request timed out after #{client.timeout}ms")}

      {:error, %Error{}} = error ->
        error

      {:error, reason} ->
        {:error, Error.new(:transport, "Snapshot request failed: #{inspect(reason)}")}
    end
  end

  @doc """
  Same as `get_proxies/2`, but returns the list directly and raises
  `Litportnet.FreeProxy.Error` instead of returning `{:error, error}`.
  """
  @spec get_proxies!(Client.t(), filters()) :: [Proxy.t()]
  def get_proxies!(%Client{} = client, filters \\ []) do
    case get_proxies(client, filters) do
      {:ok, proxies} -> proxies
      {:error, error} -> raise error
    end
  end

  @doc """
  Fetches the current snapshot, applies `filters`, and returns at most
  `count` of the highest-ranked matching proxies (that is, the first `count`
  entries of what `get_proxies/2` would have returned).
  """
  @spec pick_best(Client.t(), non_neg_integer(), filters()) ::
          {:ok, [Proxy.t()]} | {:error, Error.t()}
  def pick_best(%Client{} = client, count, filters \\ []) do
    with :ok <- validate_pick_count(count),
         {:ok, proxies} <- get_proxies(client, filters) do
      {:ok, Enum.take(proxies, count)}
    end
  end

  @doc """
  Same as `pick_best/3`, but returns the list directly and raises
  `Litportnet.FreeProxy.Error` instead of returning `{:error, error}`.
  """
  @spec pick_best!(Client.t(), non_neg_integer(), filters()) :: [Proxy.t()]
  def pick_best!(%Client{} = client, count, filters \\ []) do
    case pick_best(client, count, filters) do
      {:ok, proxies} -> proxies
      {:error, error} -> raise error
    end
  end

  # -- Filter validation ------------------------------------------------------

  defp validate_filters(filters) do
    if Keyword.keyword?(filters) do
      with :ok <- validate_known_keys(filters),
           {:ok, protocol} <- validate_protocol(Keyword.get(filters, :protocol)),
           {:ok, country} <- validate_country(Keyword.get(filters, :country)),
           {:ok, anonymity} <- validate_anonymity(Keyword.get(filters, :anonymity)),
           {:ok, https} <- validate_boolean_opt(Keyword.get(filters, :https), "https"),
           {:ok, max_latency_ms} <-
             validate_non_neg_integer_opt(Keyword.get(filters, :max_latency_ms), "max_latency_ms"),
           {:ok, min_uptime_7d} <-
             validate_non_neg_integer_opt(Keyword.get(filters, :min_uptime_7d), "min_uptime_7d"),
           {:ok, min_checks_7d} <-
             validate_non_neg_integer_opt(Keyword.get(filters, :min_checks_7d), "min_checks_7d"),
           {:ok, limit} <- validate_non_neg_integer_opt(Keyword.get(filters, :limit), "limit"),
           {:ok, checked_within_min} <-
             validate_checked_within_min(Keyword.get(filters, :checked_within_min)) do
        {:ok,
         %{
           protocol: protocol,
           country: country,
           anonymity: anonymity,
           https: https,
           max_latency_ms: max_latency_ms,
           min_uptime_7d: min_uptime_7d,
           min_checks_7d: min_checks_7d,
           limit: limit,
           checked_within_min: checked_within_min
         }}
      end
    else
      {:error, Error.new(:filter_validation, "filters must be a keyword list")}
    end
  end

  defp validate_known_keys(filters) do
    case Keyword.keys(filters) -- @known_filter_keys do
      [] ->
        :ok

      unknown ->
        names = unknown |> Enum.map(&to_string/1) |> Enum.join(", ")
        {:error, Error.new(:filter_validation, "Unknown filter option(s): #{names}")}
    end
  end

  defp validate_protocol(nil), do: {:ok, nil}

  defp validate_protocol(value) do
    if value in Proxy.protocols() do
      {:ok, value}
    else
      {:error, Error.new(:filter_validation, "protocol must be http, socks4, or socks5")}
    end
  end

  defp validate_anonymity(nil), do: {:ok, nil}

  defp validate_anonymity(value) do
    if value in Proxy.anonymities() do
      {:ok, value}
    else
      {:error, Error.new(:filter_validation, "Invalid anonymity value")}
    end
  end

  defp validate_country(nil), do: {:ok, nil}

  defp validate_country(value) when is_binary(value) do
    if Regex.match?(~r/^[a-zA-Z]{2}$/, value) do
      {:ok, String.downcase(value)}
    else
      {:error, Error.new(:filter_validation, "country must be a two-letter code")}
    end
  end

  defp validate_country(_value) do
    {:error, Error.new(:filter_validation, "country must be a two-letter code")}
  end

  defp validate_boolean_opt(nil, _name), do: {:ok, nil}
  defp validate_boolean_opt(value, _name) when is_boolean(value), do: {:ok, value}

  defp validate_boolean_opt(_value, name) do
    {:error, Error.new(:filter_validation, "#{name} must be boolean")}
  end

  defp validate_non_neg_integer_opt(nil, _name), do: {:ok, nil}

  defp validate_non_neg_integer_opt(value, _name) when is_integer(value) and value >= 0 do
    {:ok, value}
  end

  defp validate_non_neg_integer_opt(_value, name) do
    {:error, Error.new(:filter_validation, "#{name} must be a non-negative integer")}
  end

  defp validate_checked_within_min(nil), do: {:ok, 30}

  defp validate_checked_within_min(value) when is_integer(value) and value >= 1 and value <= 1440 do
    {:ok, value}
  end

  defp validate_checked_within_min(_value) do
    {:error, Error.new(:filter_validation, "checked_within_min must be from 1 to 1440")}
  end

  defp validate_pick_count(count) when is_integer(count) and count >= 0, do: :ok

  defp validate_pick_count(_count) do
    {:error, Error.new(:filter_validation, "count must be a non-negative integer")}
  end

  # -- Snapshot fetching and envelope validation ------------------------------

  defp fetch(%Client{transport: transport} = client) when is_function(transport, 2) do
    transport.(client.api_url, client.timeout)
  end

  defp fetch(%Client{} = client) do
    http_get(client.api_url, client.timeout)
  end

  defp http_get(url, timeout) do
    :ok = start_http_apps()

    http_options = [timeout: timeout, connect_timeout: timeout] ++ ssl_options(url)

    case :httpc.request(:get, {String.to_charlist(url), []}, http_options, body_format: :binary) do
      {:ok, {{_version, status, _reason_phrase}, headers, body}} ->
        {:ok, status, headers, body}

      {:error, :timeout} ->
        {:error, :timeout}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # :httpc does not verify server certificates unless it is told to, and the
  # default has changed across OTP releases. Pin verification explicitly so the
  # client behaves the same way everywhere, and fall back to the platform
  # default only where the OS trust store is not reachable.
  defp ssl_options(url) do
    if String.starts_with?(url, "https://") and cacerts_available?() do
      [
        ssl: [
          verify: :verify_peer,
          cacerts: :public_key.cacerts_get(),
          depth: 3,
          customize_hostname_check: [
            match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
          ]
        ]
      ]
    else
      []
    end
  end

  defp cacerts_available? do
    Code.ensure_loaded?(:public_key) and function_exported?(:public_key, :cacerts_get, 0)
  end

  defp start_http_apps do
    _ = Application.ensure_all_started(:inets)
    _ = Application.ensure_all_started(:ssl)
    :ok
  end

  defp validate_status(status) when is_integer(status) and status >= 200 and status <= 299 do
    :ok
  end

  defp validate_status(status) do
    {:error, Error.new(:http, "Snapshot request failed with HTTP #{status}", status)}
  end

  defp decode_body(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded} -> {:ok, decoded}
      {:error, _reason} -> {:error, Error.new(:snapshot_validation, "Malformed snapshot JSON")}
    end
  end

  defp decode_body(body), do: {:ok, body}

  defp validate_envelope(snapshot, now) do
    with {:ok, proxies} <- validate_shape(snapshot),
         :ok <- validate_not_truncated(snapshot),
         :ok <- validate_count(snapshot, proxies),
         :ok <- validate_generated_at(Map.get(snapshot, "generatedAt"), now) do
      {:ok, proxies}
    end
  end

  defp validate_shape(snapshot) when is_map(snapshot) do
    case Map.get(snapshot, "proxies") do
      proxies when is_list(proxies) -> {:ok, proxies}
      _other -> {:error, Error.new(:snapshot_validation, "Malformed snapshot envelope")}
    end
  end

  defp validate_shape(_snapshot) do
    {:error, Error.new(:snapshot_validation, "Malformed snapshot envelope")}
  end

  defp validate_not_truncated(snapshot) do
    if Map.get(snapshot, "truncated") == true do
      {:error, Error.new(:snapshot_truncated, "Snapshot is truncated")}
    else
      :ok
    end
  end

  defp validate_count(snapshot, proxies) do
    count = Map.get(snapshot, "count")
    truncated = Map.get(snapshot, "truncated")
    truncated_ok = is_nil(truncated) or is_boolean(truncated)

    if is_integer(count) and count == length(proxies) and truncated_ok do
      :ok
    else
      {:error, Error.new(:snapshot_validation, "Malformed snapshot envelope")}
    end
  end

  defp validate_generated_at(value, now) do
    case Proxy.parse_time(value) do
      nil ->
        {:error, Error.new(:snapshot_validation, "Snapshot generatedAt is outside the accepted window")}

      generated_at ->
        lower = DateTime.add(now, -120, :second)
        upper = DateTime.add(now, 5, :second)

        if DateTime.compare(generated_at, lower) != :lt and DateTime.compare(generated_at, upper) != :gt do
          :ok
        else
          {:error, Error.new(:snapshot_validation, "Snapshot generatedAt is outside the accepted window")}
        end
    end
  end

  defp map_rows(rows) do
    rows
    |> Enum.reduce_while({:ok, []}, fn row, {:ok, acc} ->
      case Proxy.from_row(row) do
        {:ok, proxy} -> {:cont, {:ok, [proxy | acc]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      {:error, _reason} = error -> error
    end
  end

  # -- Freshness, matching, sorting -------------------------------------------

  defp fresh_and_matches?(proxy, filters, now) do
    fresh?(proxy, filters.checked_within_min, now) and matches?(proxy, filters)
  end

  defp fresh?(proxy, checked_within_min, now) do
    case Proxy.parse_time(proxy.last_checked) do
      nil ->
        false

      checked_at ->
        cutoff = DateTime.add(now, -checked_within_min * 60, :second)
        upper = DateTime.add(now, 5, :second)
        DateTime.compare(checked_at, cutoff) != :lt and DateTime.compare(checked_at, upper) != :gt
    end
  end

  defp matches?(proxy, filters) do
    (is_nil(filters.protocol) or proxy.protocol == filters.protocol) and
      (is_nil(filters.country) or proxy.country == filters.country) and
      (is_nil(filters.anonymity) or proxy.anonymity == filters.anonymity) and
      (is_nil(filters.https) or proxy.https == filters.https) and
      (is_nil(filters.max_latency_ms) or
         (not is_nil(proxy.latency_ms) and proxy.latency_ms <= filters.max_latency_ms)) and
      (is_nil(filters.min_uptime_7d) or
         (not is_nil(proxy.uptime_7d) and proxy.uptime_7d >= filters.min_uptime_7d)) and
      (is_nil(filters.min_checks_7d) or proxy.checks_7d >= filters.min_checks_7d)
  end

  defp sort_and_limit(proxies, limit) do
    sorted =
      Enum.sort_by(proxies, fn proxy ->
        {
          if(is_nil(proxy.uptime_7d), do: 1, else: 0),
          -(proxy.uptime_7d || 0.0),
          if(is_nil(proxy.latency_ms), do: 1, else: 0),
          proxy.latency_ms || 0,
          proxy.url
        }
      end)

    case limit do
      nil -> sorted
      n -> Enum.take(sorted, n)
    end
  end
end
