# Live smoke check against the real snapshot API. Not part of the published Hex
# package (see the `files` list in mix.exs); it exists so CI exercises the real
# :httpc + TLS path, which the offline test suite deliberately never touches.
alias Litportnet.FreeProxy

{:ok, client} = FreeProxy.new(timeout: 20_000)

case FreeProxy.pick_best(client, 3, protocol: "socks5", checked_within_min: 1440) do
  {:ok, proxies} ->
    IO.puts("live smoke: #{length(proxies)} proxies")
    Enum.each(proxies, &IO.puts("  #{&1.url} uptime_7d=#{inspect(&1.uptime_7d)} latency_ms=#{inspect(&1.latency_ms)}"))
    if proxies == [], do: System.halt(1)

  {:error, error} ->
    IO.puts("live smoke failed: #{error.type} #{error.message}")
    System.halt(1)
end
