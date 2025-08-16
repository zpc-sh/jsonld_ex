defmodule JsonldEx do
  @moduledoc """
  High-performance JSON-LD processing library for Elixir with Rust NIF backend.
  """

  alias JsonldEx.Native

  def expand(document, opts \\ []) do
    document
    |> prepare_input()
    |> Native.expand(opts)
    |> decode_result()
  end

  def compact(document, context, opts \\ []) do
    with input <- prepare_input(document),
         ctx <- prepare_input(context) do
      input
      |> Native.compact(ctx, opts)
      |> decode_result()
    end
  end

  defp prepare_input(input) when is_binary(input), do: input
  defp prepare_input(input), do: Jason.encode!(input)

  defp decode_result({:ok, result}) when is_binary(result) do
    case Jason.decode(result) do
      {:ok, decoded} -> {:ok, decoded}
      error -> error
    end
  end
  
  defp decode_result(result), do: result
end
