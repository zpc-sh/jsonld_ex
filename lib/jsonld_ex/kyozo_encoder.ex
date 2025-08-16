defmodule JsonldEx.Kyozo.Encoder do
  @moduledoc """
  Kyozo-specific JSON-LD encoder for Claude village data.
  
  Encodes Kyozo Metal renderer Claude data into village JSON-LD format.
  """

  alias JsonldEx

  def encode_claude_village(claude_data) do
    context = %{
      "@context" => %{
        "@vocab" => "https://claudeville.dev/ontology#",
        "schema" => "https://schema.org/",
        "cv" => "https://claudeville.dev/ontology#",
        "geo" => "http://www.w3.org/2003/01/geo/wgs84_pos#",
        "kyozo" => "https://kyozo.dev/ontology#"
      }
    }

    village_data = Map.merge(context, claude_data)
    JsonldEx.compact(village_data, context["@context"])
  end

  def encode_metal_patterns(patterns) do
    Enum.map(patterns, fn pattern ->
      %{
        "@type" => "cv:Pattern",
        "kyozo:domain" => "metal_rendering",
        "schema:name" => pattern.title,
        "schema:description" => pattern.description,
        "cv:category" => pattern.category,
        "kyozo:performance" => pattern.fps_impact || 0
      }
    end)
  end
end