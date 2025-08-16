defmodule JsonldExTest do
  use ExUnit.Case
  doctest JsonldEx

  describe "expand/2" do
    test "expands a simple JSON-LD document" do
      doc = %{"@context" => "https://schema.org/", "@type" => "Person", "name" => "Jane"}
      
      assert {:ok, expanded} = JsonldEx.expand(doc)
      assert is_list(expanded)
    end
  end

  describe "compact/3" do  
    test "compacts an expanded JSON-LD document" do
      expanded = [%{"@type" => ["https://schema.org/Person"], "https://schema.org/name" => [%{"@value" => "Jane"}]}]
      context = %{"name" => "https://schema.org/name"}
      
      assert {:ok, compacted} = JsonldEx.compact(expanded, context)
      assert is_map(compacted)
    end
  end

  describe "semantic versioning" do
    test "parses semantic versions" do
      assert {:ok, parsed} = JsonldEx.parse_semantic_version("1.2.3")
      assert is_map(parsed)
    end

    test "compares versions" do
      assert :lt = JsonldEx.compare_versions("1.2.3", "1.2.4")
      assert :gt = JsonldEx.compare_versions("2.0.0", "1.9.9")
      assert :eq = JsonldEx.compare_versions("1.0.0", "1.0.0")
    end
  end
end
