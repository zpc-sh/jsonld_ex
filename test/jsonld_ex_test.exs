defmodule JsonldExTest do
  use ExUnit.Case
  doctest JsonldEx

  describe "expand/2" do
    test "expands a simple JSON-LD document" do
      doc = %{
        "@context" => %{"name" => "http://schema.org/name"},
        "@type" => "Person",
        "name" => "Jane"
      }
      
      assert {:ok, expanded} = JsonldEx.expand(doc)
      assert is_list(expanded)
      assert length(expanded) == 1
      
      [first_item] = expanded
      assert first_item["@type"] == "http://example.org/Person"
      assert first_item["http://example.org/name"] == "Jane"
    end

    test "expands with schema.org context" do
      doc = %{
        "@context" => %{"name" => "http://schema.org/name"},
        "@type" => "schema:Person",
        "name" => "John Doe"
      }
      
      assert {:ok, expanded} = JsonldEx.expand(doc)
      assert is_list(expanded)
    end

    test "handles arrays" do
      doc = %{
        "@context" => %{"items" => "http://example.org/items"},
        "items" => ["item1", "item2", "item3"]
      }
      
      assert {:ok, expanded} = JsonldEx.expand(doc)
      assert is_list(expanded)
    end

    test "handles @id expansion" do
      doc = %{
        "@context" => %{"knows" => "http://schema.org/knows"},
        "@id" => "http://example.org/person/1",
        "@type" => "Person",
        "knows" => %{"@id" => "http://example.org/person/2"}
      }
      
      assert {:ok, expanded} = JsonldEx.expand(doc)
      assert is_list(expanded)
    end
  end

  describe "compact/3" do  
    test "compacts an expanded JSON-LD document" do
      expanded = [%{
        "@type" => "http://schema.org/Person", 
        "http://schema.org/name" => "Jane"
      }]
      context = %{"name" => "http://schema.org/name"}
      
      assert {:ok, compacted} = JsonldEx.compact(expanded, context)
      assert is_map(compacted)
    end

    test "handles multiple context mappings" do
      expanded = [%{
        "@type" => "http://schema.org/Person",
        "http://schema.org/name" => "John",
        "http://schema.org/age" => 30
      }]
      context = %{
        "name" => "http://schema.org/name",
        "age" => "http://schema.org/age"
      }
      
      assert {:ok, compacted} = JsonldEx.compact(expanded, context)
      assert is_map(compacted)
    end
  end

  describe "performance" do
    test "expansion is fast" do
      doc = %{
        "@context" => %{"name" => "http://schema.org/name"},
        "@type" => "Person",
        "name" => "Speed Test"
      }
      
      # Warm up
      JsonldEx.expand(doc)
      
      {time, {:ok, _result}} = :timer.tc(fn ->
        JsonldEx.expand(doc)
      end)
      
      # Should be faster than 1ms for simple documents
      assert time < 1_000
    end
  end

  describe "error handling" do
    test "handles invalid JSON" do
      result = JsonldEx.Native.expand("invalid json", [])
      assert {:error, _reason} = result
    end

    test "handles malformed documents gracefully" do
      doc = %{"malformed" => "document", "no_context" => true}
      assert {:ok, _result} = JsonldEx.expand(doc)
    end
  end

  describe "semantic versioning" do
    test "parses semantic versions" do
      assert {:ok, result} = JsonldEx.Native.parse_semantic_version("1.2.3")
      assert is_binary(result)
      
      # Parse the JSON result
      {:ok, parsed} = Jason.decode(result)
      assert parsed["major"] == 1
      assert parsed["minor"] == 2
      assert parsed["patch"] == 3
    end

    test "compares versions correctly" do
      assert :lt = JsonldEx.Native.compare_versions("1.2.3", "1.2.4")
      assert :gt = JsonldEx.Native.compare_versions("2.0.0", "1.9.9") 
      assert :eq = JsonldEx.Native.compare_versions("1.0.0", "1.0.0")
    end

    test "handles pre-release versions" do
      assert :lt = JsonldEx.Native.compare_versions("1.0.0-alpha", "1.0.0")
      assert :gt = JsonldEx.Native.compare_versions("1.0.0", "1.0.0-alpha")
    end
  end

  describe "utility functions" do
    test "validates documents" do
      doc = Jason.encode!(%{"@context" => "http://schema.org/", "@type" => "Person"})
      # The function returns :ok for valid documents (simplified implementation)
      assert :ok = JsonldEx.Native.validate_document(doc, [])
    end

    test "caches contexts" do
      context = Jason.encode!(%{"name" => "http://schema.org/name"})
      # Returns the cache key that was used
      assert {:ok, "test_key"} = JsonldEx.Native.cache_context(context, "test_key")
    end
  end
end
