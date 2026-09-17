defmodule Litportnet.FreeProxy.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/litportnet/free-proxy-sdk"
  @homepage_url "https://litport.net/free-proxy"

  def project do
    [
      app: :litportnet_free_proxy,
      version: @version,
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      source_url: @source_url,
      homepage_url: @homepage_url
    ]
  end

  def application do
    [
      extra_applications: [:logger, :inets, :ssl]
    ]
  end

  defp deps do
    [
      {:jason, "~> 1.4"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp description do
    "Elixir client for Litport's public snapshot of verified free HTTP, SOCKS4 and SOCKS5 proxies. No API key required."
  end

  defp package do
    [
      name: "litportnet_free_proxy",
      licenses: ["MIT"],
      files: ~w(lib mix.exs README.md LICENSE),
      links: %{
        "Free proxy list" => "https://litport.net/free-proxy",
        "API documentation" => "https://litport.net/docs/free-proxy-api",
        "GitHub" => @source_url,
        "Elixir usage examples" => "#{@source_url}/tree/main/packages/elixir"
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md"],
      source_url: @source_url
    ]
  end
end
