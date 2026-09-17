defmodule Litportnet.FreeProxy.Error do
  @moduledoc """
  The error returned (or raised, by the `!` functions) by `Litportnet.FreeProxy`
  when a request, snapshot, or filter set is invalid.

  `Litportnet.FreeProxy.Error` implements the `Exception` behaviour, so every
  value of this struct can be given directly to `raise/1`. That is exactly what
  `Litportnet.FreeProxy.get_proxies!/2` and `Litportnet.FreeProxy.pick_best!/3`
  do internally.
  """

  @typedoc """
  The category of failure:

    * `:timeout` - the snapshot request did not complete before the configured timeout.
    * `:http` - the snapshot request completed but returned a non-2xx HTTP status.
    * `:snapshot_validation` - the response body was not a valid snapshot envelope
      or contained an invalid proxy row.
    * `:snapshot_truncated` - the snapshot explicitly reported itself as truncated.
    * `:filter_validation` - the options passed to `Litportnet.FreeProxy.new/1`,
      `Litportnet.FreeProxy.get_proxies/2`, or `Litportnet.FreeProxy.pick_best/3`
      were invalid.
    * `:transport` - the transport function (or the built-in HTTP transport)
      failed for a reason other than a timeout.
  """
  @type error_type ::
          :timeout
          | :http
          | :snapshot_validation
          | :snapshot_truncated
          | :filter_validation
          | :transport

  @typedoc "A `Litportnet.FreeProxy.Error` struct."
  @type t :: %__MODULE__{
          type: error_type(),
          message: String.t(),
          status: integer() | nil
        }

  defexception [:type, :message, :status]

  @doc """
  Builds a new error struct of the given `type`, with a human-readable
  `message` and an optional HTTP `status` (only meaningful for `:http`
  errors).
  """
  @spec new(error_type(), String.t(), integer() | nil) :: t()
  def new(type, message, status \\ nil) do
    %__MODULE__{type: type, message: message, status: status}
  end

  @impl Exception
  @spec message(t()) :: String.t()
  def message(%__MODULE__{message: message}), do: message
end
