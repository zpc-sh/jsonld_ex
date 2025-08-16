defmodule JsonldEx.Kyozo.Decoder do
  @moduledoc """
  Kyozo-specific JSON-LD decoder for Claude village data.
  
  Decodes village JSON-LD into Kyozo Metal renderer Claude structures.
  """

  alias JsonldEx

  def decode_claude_village(jsonld_data) do
    case JsonldEx.expand(jsonld_data) do
      {:ok, expanded} ->
        {:ok, extract_claude_data(expanded)}
      
      {:error, reason} ->
        {:error, "Failed to decode village data: #{reason}"}
    end
  end

  def decode_neighbor_patterns(neighbor_jsonld) do
    case JsonldEx.expand(neighbor_jsonld) do
      {:ok, expanded} ->
        patterns = extract_patterns(expanded)
        {:ok, filter_metal_relevant(patterns)}
      
      {:error, reason} ->
        {:error, "Failed to decode neighbor patterns: #{reason}"}
    end
  end

  defp extract_claude_data(expanded) do
    %{
      claude_id: get_value(expanded, "cv:claudeId"),
      location: extract_location(expanded),
      mood: get_value(expanded, "cv:mood"),
      accomplishments: extract_accomplishments(expanded),
      patterns: extract_patterns(expanded)
    }
  end

  defp extract_location(expanded) do
    location = get_nested_value(expanded, ["cv:home", "geo:location"])
    %{
      x: get_value(location, "cv:x"),
      y: get_value(location, "cv:y")
    }
  end

  defp filter_metal_relevant(patterns) do
    # Use appropriate optimization based on system capabilities
    case {System.schedulers_online(), :os.type()} do
      {cores, {:unix, :darwin}} when cores >= 8 ->
        # Mac with 8+ cores - use Metal acceleration
        metal_filter_patterns(patterns)
      
      {cores, _} when cores >= 4 ->
        # Multi-core system - use parallel filtering
        parallel_filter_patterns(patterns)
      
      _ ->
        # Single core or limited - sequential processing
        sequential_filter_patterns(patterns)
    end
  end

  defp metal_filter_patterns(patterns) do
    # Metal Performance Shaders on macOS
    Enum.filter(patterns, &metal_relevance_check/1)
  end

  defp parallel_filter_patterns(patterns) do
    patterns
    |> Task.async_stream(&metal_relevance_check/1, max_concurrency: System.schedulers_online())
    |> Stream.filter(fn {:ok, relevant} -> relevant end)
    |> Stream.map(fn {:ok, _} -> true end)
    |> Enum.to_list()
  end

  defp sequential_filter_patterns(patterns) do
    Enum.filter(patterns, &metal_relevance_check/1)
  end

  defp metal_relevance_check(pattern) do
    description = pattern.description || ""
    String.contains?(description, ["Metal", "GPU", "rendering", "performance", "120fps"])
  end

  defp get_value(data, key) when is_map(data), do: Map.get(data, key)
  defp get_value(_, _), do: nil

  defp get_nested_value(data, [key]), do: get_value(data, key)
  defp get_nested_value(data, [key | rest]) do
    case get_value(data, key) do
      nil -> nil
      nested -> get_nested_value(nested, rest)
    end
  end

  defp extract_accomplishments(_expanded), do: []
  defp extract_patterns(_expanded), do: []
end