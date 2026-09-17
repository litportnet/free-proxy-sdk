defmodule Litportnet.FreeProxy.Client do
  @moduledoc """
  Configuration for talking to the Litport free-proxy snapshot API.

  Build one with `new/1` - normally via `Litportnet.FreeProxy.new/1`, which
  simply delegates to this module. A `t:t/0` is an immutable struct; it holds
  the request URL, timeout, and the optional `transport`/`now` overrides used
  in tests. It does not hold a socket or any other live resource.
  """

  alias Litportnet.FreeProxy.Error

  @default_api_url "https://litport.net/api/free-proxy/snapshot?checkedWithinMin=1440"
  @default_timeout 10_000

  @typedoc """
  A pluggable HTTP transport. Given the request URL and the configured
  timeout (in milliseconds), it must return `{:ok, status, headers, body}`,
  `{:error, :timeout}`, or `{:error, reason}`. `headers` is a list of
  `{key, value}` pairs and `body` is the raw response body (a binary, or
  already-decoded JSON term).

  Tests pass a `transport` fun to get deterministic, offline responses
  instead of making a real HTTP request.
  """
  @type transport_fun ::
          (String.t(), pos_integer() ->
             {:ok, integer(), list(), binary() | term()}
             | {:error, :timeout}
             | {:error, term()})

  @typedoc "Returns the current time as a `DateTime.t()`. Overridable for deterministic tests."
  @type now_fun :: (-> DateTime.t())

  @typedoc "A `Litportnet.FreeProxy.Client` struct."
  @type t :: %__MODULE__{
          api_url: String.t(),
          timeout: pos_integer(),
          transport: transport_fun() | nil,
          now: now_fun()
        }

  defstruct api_url: @default_api_url,
            timeout: @default_timeout,
            transport: nil,
            now: &DateTime.utc_now/0

  @doc """
  Builds a new client.

  ## Options

    * `:api_url` - the snapshot endpoint to request. Defaults to
      `#{@default_api_url}`.
    * `:timeout` - the request timeout in milliseconds. Must be a positive
      integer. Defaults to `#{@default_timeout}`.
    * `:transport` - an optional 2-arity function; see `t:transport_fun/0`.
      When omitted, requests are made with Erlang's built-in `:httpc`.
    * `:now` - an optional 0-arity function returning the current
      `DateTime.t()`. Defaults to `&DateTime.utc_now/0`. Overriding it makes
      snapshot-freshness validation deterministic in tests.

  Returns `{:error, %Litportnet.FreeProxy.Error{type: :filter_validation}}` if
  any option is invalid.
  """
  @spec new(keyword()) :: {:ok, t()} | {:error, Error.t()}
  def new(opts \\ []) do
    if Keyword.keyword?(opts) do
      api_url = Keyword.get(opts, :api_url, @default_api_url)
      timeout = Keyword.get(opts, :timeout, @default_timeout)
      transport = Keyword.get(opts, :transport)
      now = Keyword.get(opts, :now, &DateTime.utc_now/0)

      with :ok <- validate_api_url(api_url),
           :ok <- validate_timeout(timeout),
           :ok <- validate_transport(transport),
           :ok <- validate_now(now) do
        {:ok, %__MODULE__{api_url: api_url, timeout: timeout, transport: transport, now: now}}
      end
    else
      {:error, Error.new(:filter_validation, "options must be a keyword list")}
    end
  end

  defp validate_api_url(value) when is_binary(value), do: :ok

  defp validate_api_url(_value) do
    {:error, Error.new(:filter_validation, "api_url must be a string")}
  end

  defp validate_timeout(value) when is_integer(value) and value > 0, do: :ok

  defp validate_timeout(_value) do
    {:error, Error.new(:filter_validation, "timeout must be a positive integer")}
  end

  defp validate_transport(nil), do: :ok
  defp validate_transport(fun) when is_function(fun, 2), do: :ok

  defp validate_transport(_value) do
    {:error, Error.new(:filter_validation, "transport must be a 2-arity function")}
  end

  defp validate_now(fun) when is_function(fun, 0), do: :ok

  defp validate_now(_value) do
    {:error, Error.new(:filter_validation, "now must be a 0-arity function")}
  end
end
