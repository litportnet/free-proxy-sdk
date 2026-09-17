defmodule Litportnet.FreeProxy.Proxy do
  @moduledoc """
  A single normalized free-proxy record, as returned inside the list from
  `Litportnet.FreeProxy.get_proxies/2` and `Litportnet.FreeProxy.pick_best/3`.

  Every field below is documented with the raw snapshot field it was derived
  from. `Litportnet.FreeProxy.Proxy.from_row/1` is the function that performs
  that mapping and validation; it is used internally by `Litportnet.FreeProxy`
  and is exposed publicly mostly so its validation rules are easy to find and
  audit.
  """

  alias Litportnet.FreeProxy.Error

  @protocols ~w(http socks4 socks5)
  @anonymities ~w(transparent anonymous elite unknown)

  @country_regex ~r/^[a-zA-Z]{2}$/
  @asn_regex ~r/^AS(\d+)$/
  @timestamp_regex ~r/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$/

  # IPv4 ranges that are never returned by a legitimate public snapshot:
  # unspecified/this-network, private, shared address space (CGNAT),
  # loopback, link-local, benchmarking/documentation/test ranges,
  # multicast, and reserved.
  @blocked_ranges [
    {{0, 0, 0, 0}, 8},
    {{10, 0, 0, 0}, 8},
    {{100, 64, 0, 0}, 10},
    {{127, 0, 0, 0}, 8},
    {{169, 254, 0, 0}, 16},
    {{172, 16, 0, 0}, 12},
    {{192, 0, 0, 0}, 24},
    {{192, 0, 2, 0}, 24},
    {{192, 168, 0, 0}, 16},
    {{198, 18, 0, 0}, 15},
    {{198, 51, 100, 0}, 24},
    {{203, 0, 113, 0}, 24},
    {{224, 0, 0, 0}, 4},
    {{240, 0, 0, 0}, 4}
  ]

  @typedoc "A normalized free-proxy record."
  @type t :: %__MODULE__{
          protocol: String.t(),
          ip: String.t(),
          port: pos_integer(),
          url: String.t(),
          country: String.t() | nil,
          region: String.t() | nil,
          city: String.t() | nil,
          timezone: String.t() | nil,
          asn: non_neg_integer() | nil,
          asn_org: String.t() | nil,
          anonymity: String.t(),
          https: boolean() | nil,
          latency_ms: integer() | nil,
          latency_median_ms: float() | nil,
          uptime_24h: float() | nil,
          uptime_7d: float() | nil,
          checks_7d: non_neg_integer(),
          exit_ip: String.t() | nil,
          sources_count: non_neg_integer(),
          first_seen: String.t(),
          last_checked: String.t()
        }

  defstruct [
    :protocol,
    :ip,
    :port,
    :url,
    :country,
    :region,
    :city,
    :timezone,
    :asn,
    :asn_org,
    :anonymity,
    :https,
    :latency_ms,
    :latency_median_ms,
    :uptime_24h,
    :uptime_7d,
    :checks_7d,
    :exit_ip,
    :sources_count,
    :first_seen,
    :last_checked
  ]

  @doc "The proxy protocols accepted by the snapshot API and by the `:protocol` filter."
  @spec protocols() :: [String.t()]
  def protocols, do: @protocols

  @doc "The anonymity levels accepted by the snapshot API and by the `:anonymity` filter."
  @spec anonymities() :: [String.t()]
  def anonymities, do: @anonymities

  @doc """
  Builds a normalized `t:t/0` from a raw snapshot row (a JSON object decoded
  into a map with string keys), validating every field.

  Returns `{:error, %Litportnet.FreeProxy.Error{type: :snapshot_validation}}`
  if the row is not a map, or if any field fails validation - most notably
  when `host` is not a public IPv4 address. `uptime_7d` is set to `nil`
  whenever `checks7d` is below `50`, regardless of what the raw snapshot
  reported for `uptime7d`.
  """
  @spec from_row(term()) :: {:ok, t()} | {:error, Error.t()}
  def from_row(row) when is_map(row) do
    with {:ok, protocol} <- validate_protocol(Map.get(row, "protocol")),
         {:ok, ip} <- validate_ip(Map.get(row, "host")),
         {:ok, port} <- validate_port(Map.get(row, "port")),
         {:ok, anonymity} <- validate_anonymity(Map.get(row, "anonymity")),
         {:ok, country} <- validate_country(Map.get(row, "geoCountry")),
         {:ok, asn} <- validate_asn(Map.get(row, "asn")),
         {:ok, region} <- validate_nullable_string(Map.get(row, "geoRegion")),
         {:ok, city} <- validate_nullable_string(Map.get(row, "geoCity")),
         {:ok, timezone} <- validate_nullable_string(Map.get(row, "geoTimezone")),
         {:ok, asn_org} <- validate_nullable_string(Map.get(row, "asnOrgName")),
         {:ok, exit_ip} <- validate_nullable_string(Map.get(row, "externalIp")),
         {:ok, https} <- validate_nullable_boolean(Map.get(row, "https")),
         {:ok, latency_ms} <- validate_nullable_number(Map.get(row, "responseTimeMs")),
         {:ok, latency_median_ms} <- validate_nullable_number(Map.get(row, "responseTimeMedianMs")),
         {:ok, uptime_24h} <- validate_nullable_number(Map.get(row, "uptime24h")),
         {:ok, uptime_7d_raw} <- validate_nullable_number(Map.get(row, "uptime7d")),
         {:ok, checks_7d} <- validate_non_neg_integer(Map.get(row, "checks7d")),
         {:ok, sources_count} <- validate_non_neg_integer(Map.get(row, "sourcesCount")),
         {:ok, first_seen} <- validate_timestamp(Map.get(row, "createdAt")),
         {:ok, last_checked} <- validate_timestamp(Map.get(row, "pingAt")) do
      uptime_7d = if checks_7d < 50, do: nil, else: nullable_float(uptime_7d_raw)

      {:ok,
       %__MODULE__{
         protocol: protocol,
         ip: ip,
         port: port,
         url: "#{protocol}://#{ip}:#{port}",
         country: country,
         region: region,
         city: city,
         timezone: timezone,
         asn: asn,
         asn_org: asn_org,
         anonymity: anonymity,
         https: https,
         latency_ms: nullable_round(latency_ms),
         latency_median_ms: nullable_float(latency_median_ms),
         uptime_24h: nullable_float(uptime_24h),
         uptime_7d: uptime_7d,
         checks_7d: checks_7d,
         exit_ip: exit_ip,
         sources_count: sources_count,
         first_seen: first_seen,
         last_checked: last_checked
       }}
    end
  end

  def from_row(_row) do
    {:error, Error.new(:snapshot_validation, "Snapshot contains an invalid proxy row")}
  end

  @doc """
  Parses an ISO-8601 UTC timestamp string, returning `nil` when `value` is not
  a binary, does not match the expected `YYYY-MM-DDTHH:MM:SS[.ffffff](Z|±HH:MM)`
  shape, or is not a real calendar date/time (for example, February 30th).
  """
  @spec parse_time(term()) :: DateTime.t() | nil
  def parse_time(value) when is_binary(value) do
    if Regex.match?(@timestamp_regex, value) do
      case DateTime.from_iso8601(value) do
        {:ok, datetime, _utc_offset} -> datetime
        {:error, _reason} -> nil
      end
    else
      nil
    end
  end

  def parse_time(_value), do: nil

  defp validate_protocol(value) when value in @protocols, do: {:ok, value}

  defp validate_protocol(_value) do
    {:error, Error.new(:snapshot_validation, "Snapshot contains an invalid proxy row")}
  end

  defp validate_ip(value) do
    if public_ipv4?(value) do
      {:ok, value}
    else
      {:error, Error.new(:snapshot_validation, "Snapshot contains an invalid proxy row")}
    end
  end

  defp validate_port(value) when is_integer(value) and value >= 1 and value <= 65_535 do
    {:ok, value}
  end

  defp validate_port(_value) do
    {:error, Error.new(:snapshot_validation, "Snapshot contains an invalid proxy row")}
  end

  defp validate_anonymity(value) when value in @anonymities, do: {:ok, value}

  defp validate_anonymity(_value) do
    {:error, Error.new(:snapshot_validation, "Snapshot contains an invalid proxy row")}
  end

  defp validate_country(nil), do: {:ok, nil}

  defp validate_country(value) when is_binary(value) do
    if Regex.match?(@country_regex, value) do
      {:ok, String.downcase(value)}
    else
      {:error, Error.new(:snapshot_validation, "Invalid country")}
    end
  end

  defp validate_country(_value) do
    {:error, Error.new(:snapshot_validation, "Invalid country")}
  end

  defp validate_asn(nil), do: {:ok, nil}
  defp validate_asn(value) when is_integer(value) and value >= 0, do: {:ok, value}

  defp validate_asn(value) when is_binary(value) do
    case Regex.run(@asn_regex, value) do
      [_full, digits] -> {:ok, String.to_integer(digits)}
      nil -> {:error, Error.new(:snapshot_validation, "Invalid ASN")}
    end
  end

  defp validate_asn(_value) do
    {:error, Error.new(:snapshot_validation, "Invalid ASN")}
  end

  defp validate_nullable_string(nil), do: {:ok, nil}
  defp validate_nullable_string(value) when is_binary(value), do: {:ok, value}

  defp validate_nullable_string(_value) do
    {:error, Error.new(:snapshot_validation, "Invalid nullable string")}
  end

  defp validate_nullable_boolean(nil), do: {:ok, nil}
  defp validate_nullable_boolean(value) when is_boolean(value), do: {:ok, value}

  defp validate_nullable_boolean(_value) do
    {:error, Error.new(:snapshot_validation, "Invalid https value")}
  end

  defp validate_nullable_number(nil), do: {:ok, nil}
  defp validate_nullable_number(value) when is_number(value), do: {:ok, value}

  defp validate_nullable_number(_value) do
    {:error, Error.new(:snapshot_validation, "Invalid nullable number")}
  end

  defp validate_non_neg_integer(value) when is_integer(value) and value >= 0, do: {:ok, value}

  defp validate_non_neg_integer(_value) do
    {:error, Error.new(:snapshot_validation, "Invalid count")}
  end

  defp validate_timestamp(value) do
    case parse_time(value) do
      nil -> {:error, Error.new(:snapshot_validation, "Invalid timestamp")}
      datetime -> {:ok, to_iso_millis(datetime)}
    end
  end

  defp to_iso_millis(datetime) do
    datetime
    |> DateTime.truncate(:millisecond)
    |> DateTime.to_iso8601()
  end

  defp nullable_float(nil), do: nil
  defp nullable_float(value) when is_number(value), do: value * 1.0

  defp nullable_round(nil), do: nil
  defp nullable_round(value) when is_integer(value), do: value
  defp nullable_round(value) when is_float(value), do: round(value)

  defp public_ipv4?(value) when is_binary(value) do
    case :inet.parse_ipv4strict_address(String.to_charlist(value)) do
      {:ok, ip} -> not Enum.any?(@blocked_ranges, fn {net, bits} -> same_network?(ip, net, bits) end)
      {:error, _reason} -> false
    end
  end

  defp public_ipv4?(_value), do: false

  # `net` is always the aligned network address for `bits`, so two addresses
  # share the network when they fall in the same `block_size`-sized bucket -
  # this avoids any bitmask arithmetic.
  defp same_network?(ip, net, bits) do
    block_size = Integer.pow(2, 32 - bits)
    div(ip_to_int(ip), block_size) == div(ip_to_int(net), block_size)
  end

  defp ip_to_int({a, b, c, d}), do: a * 16_777_216 + b * 65_536 + c * 256 + d
end
