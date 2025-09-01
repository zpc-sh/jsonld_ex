defmodule JsonldEx.C14n do
  @moduledoc """
  Canonicalization, hashing, and equality helpers for JSON-LD.

  Provides Elixir fallbacks when NIFs are unavailable. Uses
  JsonldEx.Diff.Performance.normalize_rdf_graph/3 for URDNA2015-style
  canonicalization output when possible.
  """

  alias JsonldEx.Diff.Performance, as: Perf

  @type hash_form :: :urdna2015_nquads | :stable_json

  @doc """
  Canonicalize a JSON(-LD) term. Returns N-Quads-like string and a bnode map if available.

  Options:
  - algorithm: :urdna2015 (default)
  """
  def c14n(term, opts \\ []) do
    :telemetry.execute([:jsonld, :canonicalize, :start], %{}, %{opts: opts})
    alg = Keyword.get(opts, :algorithm, :urdna2015)
    provider = provider()
    key = {:c14n, provider, alg, stable_key(term)}
    with {:miss, nil} <- {:miss, cache_get(key)},
         result <- Perf.normalize_rdf_graph(term, alg, opts) do
      case result do
        {:ok, nquads} when is_binary(nquads) ->
          cache_put(key, nquads)
          :telemetry.execute([:jsonld, :canonicalize, :stop], %{}, %{algorithm: alg, provider: provider, bytes: byte_size(nquads)})
          {:ok, %{nquads: nquads, bnode_map: %{}}}
        {:error, reason} ->
          :telemetry.execute([:jsonld, :canonicalize, :error], %{}, %{provider: provider, reason: reason})
          {:error, :canonicalization_failed}
        other ->
          :telemetry.execute([:jsonld, :canonicalize, :error], %{}, %{provider: provider, reason: other})
          {:error, :canonicalization_failed}
      end
    else
      {:miss, cached} when is_binary(cached) ->
        :telemetry.execute([:jsonld, :canonicalize, :stop], %{}, %{algorithm: alg, provider: provider, bytes: byte_size(cached), cache: :hit})
        {:ok, %{nquads: cached, bnode_map: %{}}}
    end
  end

  @doc """
  Compute a deterministic hash of a JSON(-LD) term.

  Options:
  - form: :urdna2015_nquads | :stable_json (default: :urdna2015_nquads)
  - algorithm: :sha256 (fixed)
  """
  def hash(term, opts \\ []) do
    :telemetry.execute([:jsonld, :hash, :start], %{}, %{opts: opts})
    form = Keyword.get(opts, :form, :stable_json)
    data =
      case form do
        :urdna2015_nquads ->
          case c14n(term, Keyword.put_new(opts, :algorithm, :urdna2015)) do
            {:ok, %{nquads: nq}} -> nq
            _ -> canonical_json(term)
          end
        :stable_json -> canonical_json(term)
        other -> raise ArgumentError, "unsupported form: #{inspect(other)}"
      end

    digest = :crypto.hash(:sha256, data) |> Base.encode16(case: :lower)
    :telemetry.execute([:jsonld, :hash, :stop], %{}, %{bytes: byte_size(data)})
    {:ok, %{algorithm: :sha256, form: form, hash: digest, quad_count: count_lines(data)}}
  end

  @doc """
  Compare two JSON(-LD) terms for canonical equality.

  Options:
  - no_remote: true (ignored here; present for API compatibility)
  - form: :urdna2015_nquads | :stable_json (default: :urdna2015_nquads)
  """
  def equal?(a, b, opts \\ []) do
    form = Keyword.get(opts, :form, :urdna2015_nquads)
    {:ok, h1} = hash(a, form: form)
    {:ok, h2} = hash(b, form: form)
    h1.hash == h2.hash
  end

  defp canonical_json(value) do
    encode_sorted(value)
  end

  defp stable_key(term) do
    :crypto.hash(:sha256, canonical_json(term)) |> Base.encode16(case: :lower)
  end

  defp encode_sorted(map) when is_map(map) do
    # Encode maps with sorted keys, recursively
    keys = map |> Map.keys() |> Enum.map(&to_string/1) |> Enum.sort()
    inner =
      Enum.map(keys, fn k ->
        v = Map.fetch!(map, key_lookup(map, k))
        encoded_v = encode_sorted(v)
        ~s("#{escape(k)}":) <> encoded_v
      end)
      |> Enum.join(",")
    "{" <> inner <> "}"
  end
  defp encode_sorted(list) when is_list(list) do
    "[" <> Enum.map_join(list, ",", &encode_sorted/1) <> "]"
  end
  defp encode_sorted(v) when is_binary(v), do: Jason.encode!(v)
  defp encode_sorted(v) when is_number(v) or is_boolean(v) or is_nil(v), do: Jason.encode!(v)

  defp key_lookup(map, string_key) do
    # Map keys may be atoms or strings; prefer exact string key else atom
    cond do
      Map.has_key?(map, string_key) -> string_key
      Map.has_key?(map, String.to_atom(string_key)) -> String.to_atom(string_key)
      true -> string_key
    end
  end

  defp escape(s), do: s |> String.replace("\"", "\\\"")
  defp count_lines(bin) when is_binary(bin), do: bin |> String.split("\n") |> Enum.reject(&(&1 == "")) |> length()

  # Provider selection: ENV takes precedence, then application env, then :none.
  defp provider do
    case System.get_env("JSONLD_CANON_PROVIDER") do
      nil ->
        # If not explicitly set, infer from NIF features: prefer :ssi when requested
        inferred =
          case System.get_env("JSONLD_NIF_FEATURES") do
            nil -> :none
            "" -> :none
            feats -> if String.contains?(feats, "ssi_urdna2015"), do: :ssi, else: :none
          end
        Application.get_env(:jsonld_ex, :canon_provider, inferred)
      s -> String.to_atom(String.downcase(s))
    end
  rescue
    _ -> :none
  end

  # Simple ETS-backed cache
  @table :jsonld_c14n_cache
  defp ensure_table do
    case :ets.whereis(@table) do
      :undefined -> :ets.new(@table, [:set, :public, :named_table, {:read_concurrency, true}])
      _ -> @table
    end
  end
  defp cache_get(key) do
    ensure_table()
    case :ets.lookup(@table, key) do
      [{^key, val}] -> val
      _ -> nil
    end
  end
  defp cache_put(key, val) do
    ensure_table()
    :ets.insert(@table, {key, val})
    :ok
  end
end
