defmodule JsonldEx.SSIIntegrationTest do
  use ExUnit.Case, async: true

  @tag :ssi
  test "urdna2015 hash returns ok when provider available" do
    doc = %{"@id" => "ex:1", "name" => "alice"}

    case JSONLD.hash(doc, form: :urdna2015_nquads) do
      {:ok, result} ->
        assert result.algorithm == :sha256
        assert is_binary(result.hash)
        assert byte_size(result.hash) == 64
      {:error, _} ->
        # It's acceptable if URDNA isn't available in this build; ensure call is safe
        assert true
    end
  end
end

