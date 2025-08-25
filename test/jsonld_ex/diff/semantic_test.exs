defmodule JsonldEx.Diff.SemanticTest do
  use ExUnit.Case, async: true

  alias JsonldEx.Diff.Semantic

  describe "semantic diff generation" do
    test "detects semantic changes in JSON-LD documents" do
      old = %{
        "@context" => %{"name" => "http://schema.org/name"},
        "@id" => "http://example.com/person/1",
        "name" => "John Doe"
      }
      
      new = %{
        "@context" => %{"name" => "http://schema.org/name"},
        "@id" => "http://example.com/person/1",
        "name" => "Jane Doe"
      }

      {:ok, diff} = Semantic.diff(old, new)
      
      assert is_list(diff.added_triples)
      assert is_list(diff.removed_triples)
      assert is_list(diff.modified_nodes)
      
      # Should detect the name change at the RDF level
      assert length(diff.modified_nodes) > 0
    end

    test "detects context changes" do
      old = %{
        "@context" => %{"name" => "http://schema.org/name"},
        "@id" => "http://example.com/person/1",
        "name" => "John Doe"
      }
      
      new = %{
        "@context" => %{
          "name" => "http://schema.org/name",
          "age" => "http://schema.org/age"
        },
        "@id" => "http://example.com/person/1", 
        "name" => "John Doe",
        "age" => 30
      }

      {:ok, diff} = Semantic.diff(old, new, context_aware: true)
      
      assert diff.context_changes.added_mappings["age"] == "http://schema.org/age"
    end

    test "handles different context representations with same meaning" do
      old = %{
        "@context" => %{"name" => "http://schema.org/name"},
        "@id" => "http://example.com/person/1",
        "name" => "John Doe"
      }
      
      new = %{
        "@context" => "http://schema.org/",
        "@id" => "http://example.com/person/1",
        "name" => "John Doe"
      }

      {:ok, diff} = Semantic.diff(old, new)
      
      # Should recognize these as semantically equivalent
      # (though context representation changed)
      assert diff.metadata.semantic_equivalence == true or 
             (length(diff.added_triples) == 0 and length(diff.removed_triples) == 0)
    end

    test "detects type additions" do
      old = %{
        "@context" => "http://schema.org/",
        "@id" => "http://example.com/person/1",
        "name" => "John Doe"
      }
      
      new = %{
        "@context" => "http://schema.org/",
        "@id" => "http://example.com/person/1",
        "@type" => "Person",
        "name" => "John Doe"
      }

      {:ok, diff} = Semantic.diff(old, new)
      
      # Should detect the type addition
      person_node = Enum.find(diff.modified_nodes, &(&1.node_id == "http://example.com/person/1"))
      
      if person_node do
        type_addition = Enum.find(person_node.added_properties, fn prop ->
          String.contains?(prop.property, "type") or prop.property == "http://www.w3.org/1999/02/22-rdf-syntax-ns#type"
        end)
        
        assert type_addition != nil
      else
        # Alternative: check if there are added triples for type
        assert length(diff.added_triples) > 0
      end
    end

    test "handles blank nodes" do
      old = %{
        "@context" => "http://schema.org/",
        "@id" => "http://example.com/person/1",
        "name" => "John Doe",
        "address" => %{
          "streetAddress" => "123 Main St",
          "addressCity" => "Anytown"
        }
      }
      
      new = %{
        "@context" => "http://schema.org/",
        "@id" => "http://example.com/person/1",
        "name" => "John Doe",
        "address" => %{
          "streetAddress" => "456 Oak Ave", 
          "addressCity" => "Anytown"
        }
      }

      {:ok, diff} = Semantic.diff(old, new, blank_node_strategy: :uuid)
      
      # Should detect changes in the blank node (address)
      assert length(diff.added_triples) > 0 or length(diff.removed_triples) > 0 or
             length(diff.modified_nodes) > 0
    end

    test "treats different blank node ids as equivalent" do
      old = %{
        "@context" => %{"name" => "http://schema.org/name", "knows" => "http://schema.org/knows"},
        "@id" => "http://example.com/person/1",
        "knows" => [%{"@id" => "_:a", "name" => "Alice"}]
      }

      new = %{
        "@context" => %{"name" => "http://schema.org/name", "knows" => "http://schema.org/knows"},
        "@id" => "http://example.com/person/1",
        "knows" => [%{"@id" => "_:b", "name" => "Alice"}]
      }

      {:ok, diff} = Semantic.diff(old, new)
      assert diff.metadata.semantic_equivalence == true
      assert length(diff.added_triples) == 0
      assert length(diff.removed_triples) == 0
    end

    test "groups property changes under modified_properties" do
      old = %{
        "@context" => %{"name" => "http://schema.org/name"},
        "@id" => "http://example.com/person/1",
        "name" => "John"
      }

      new = %{
        "@context" => %{"name" => "http://schema.org/name"},
        "@id" => "http://example.com/person/1",
        "name" => "Jane"
      }

      {:ok, diff} = Semantic.diff(old, new)
      node = Enum.find(diff.modified_nodes, &(&1.node_id == "http://example.com/person/1"))
      assert node
      # Ensure name change is captured as modified, not separate add/remove
      mod = Enum.find(node.modified_properties, &(&1.property == "http://schema.org/name"))
      assert mod
      assert mod.old_value == "John" or (is_map(mod.old_value) and Map.get(mod.old_value, :value) == "John")
      assert mod.new_value == "Jane" or (is_map(mod.new_value) and Map.get(mod.new_value, :value) == "Jane")
      refute Enum.any?(node.added_properties, &(&1.property == "http://schema.org/name"))
      refute Enum.any?(node.removed_properties, &(&1.property == "http://schema.org/name"))
    end
  end

  describe "semantic patching" do
    test "applies RDF-level changes correctly" do
      document = %{
        "@context" => "http://schema.org/",
        "@id" => "http://example.com/person/1",
        "name" => "John Doe"
      }
      
      # Create a simple semantic diff
      diff = %{
        added_triples: [
          %{
            subject: "http://example.com/person/1",
            predicate: "http://www.w3.org/1999/02/22-rdf-syntax-ns#type",
            object: "http://schema.org/Person"
          }
        ],
        removed_triples: [],
        modified_nodes: [],
        context_changes: %{
          added_mappings: %{},
          removed_mappings: %{},
          changed_mappings: %{},
          base_changes: {nil, nil}
        },
        metadata: %{}
      }

      {:ok, result} = Semantic.patch(document, diff)
      
      # Should have added the type
      assert result["@type"] == "Person" or 
             (is_list(result["@type"]) and Enum.member?(result["@type"], "Person"))
    end

    test "applies context changes" do
      document = %{
        "@context" => %{"name" => "http://schema.org/name"},
        "@id" => "http://example.com/person/1",
        "name" => "John Doe"
      }
      
      diff = %{
        added_triples: [],
        removed_triples: [],
        modified_nodes: [],
        context_changes: %{
          added_mappings: %{"age" => "http://schema.org/age"},
          removed_mappings: %{},
          changed_mappings: %{},
          base_changes: {nil, nil}
        },
        metadata: %{}
      }

      {:ok, result} = Semantic.patch(document, diff)
      
      # Should have added the age mapping to context
      assert result["@context"]["age"] == "http://schema.org/age"
    end

    test "applies predicate add/remove at root" do
      document = %{
        "@context" => %{"name" => "http://schema.org/name", "age" => "http://schema.org/age"},
        "@id" => "http://example.com/person/1",
        "name" => "John"
      }

      diff = %{
        added_triples: [
          %{subject: "http://example.com/person/1", predicate: "http://schema.org/name", object: "Jane"},
          %{subject: "http://example.com/person/1", predicate: "http://schema.org/age", object: %{value: "30", type: "http://www.w3.org/2001/XMLSchema#integer"}}
        ],
        removed_triples: [
          %{subject: "http://example.com/person/1", predicate: "http://schema.org/name", object: "John"}
        ],
        modified_nodes: [],
        context_changes: %{added_mappings: %{}, removed_mappings: %{}, changed_mappings: %{}, base_changes: {nil, nil}},
        metadata: %{}
      }

      {:ok, result} = Semantic.patch(document, diff)
      assert result["name"] == "Jane"
      assert result["age"] == 30
    end
  end

  describe "diff merging" do
    test "merges semantic diffs correctly" do
      diff1 = %{
        added_triples: [
          %{subject: "http://example.com/1", predicate: "http://schema.org/name", object: "John"}
        ],
        removed_triples: [],
        modified_nodes: [],
        context_changes: %{added_mappings: %{"name" => "http://schema.org/name"}, removed_mappings: %{}, changed_mappings: %{}, base_changes: {nil, nil}},
        metadata: %{}
      }
      
      diff2 = %{
        added_triples: [
          %{subject: "http://example.com/1", predicate: "http://schema.org/age", object: "30"}
        ],
        removed_triples: [],
        modified_nodes: [],
        context_changes: %{added_mappings: %{"age" => "http://schema.org/age"}, removed_mappings: %{}, changed_mappings: %{}, base_changes: {nil, nil}},
        metadata: %{}
      }

      {:ok, merged} = Semantic.merge_diffs([diff1, diff2])
      
      assert length(merged.added_triples) == 2
      assert merged.context_changes.added_mappings["name"] == "http://schema.org/name"
      assert merged.context_changes.added_mappings["age"] == "http://schema.org/age"
    end
  end

  describe "inverse operations" do
    test "inverts semantic diffs correctly" do
      diff = %{
        added_triples: [
          %{subject: "http://example.com/1", predicate: "http://schema.org/name", object: "John"}
        ],
        removed_triples: [
          %{subject: "http://example.com/1", predicate: "http://schema.org/age", object: "30"}
        ],
        modified_nodes: [
          %{
            node_id: "http://example.com/1",
            added_properties: [%{property: "http://schema.org/city", new_value: "NYC"}],
            removed_properties: [%{property: "http://schema.org/country", old_value: "USA"}],
            modified_properties: [%{property: "http://schema.org/name", old_value: "Jane", new_value: "John"}]
          }
        ],
        context_changes: %{
          added_mappings: %{"city" => "http://schema.org/city"},
          removed_mappings: %{"country" => "http://schema.org/country"},
          changed_mappings: %{},
          base_changes: {nil, nil}
        },
        metadata: %{}
      }

      {:ok, inverse} = Semantic.inverse(diff)
      
      # Added triples become removed triples
      assert inverse.removed_triples == diff.added_triples
      assert inverse.added_triples == diff.removed_triples
      
      # Context changes are inverted
      assert inverse.context_changes.removed_mappings == diff.context_changes.added_mappings
      assert inverse.context_changes.added_mappings == diff.context_changes.removed_mappings
      
      # Node modifications are inverted
      inverted_node = hd(inverse.modified_nodes)
      original_node = hd(diff.modified_nodes)
      
      assert inverted_node.added_properties == original_node.removed_properties
      assert inverted_node.removed_properties == original_node.added_properties
      
      # Modified properties have old/new values swapped
      inverted_prop = hd(inverted_node.modified_properties)
      original_prop = hd(original_node.modified_properties)
      
      assert inverted_prop.old_value == original_prop.new_value
      assert inverted_prop.new_value == original_prop.old_value
    end
  end

  describe "validation" do
    test "validates semantic patches" do
      document = %{
        "@context" => "http://schema.org/",
        "@id" => "http://example.com/person/1",
        "name" => "John Doe"
      }
      
      valid_diff = %{
        added_triples: [],
        removed_triples: [
          %{
            subject: "http://example.com/person/1",
            predicate: "http://schema.org/name",
            object: "John Doe"
          }
        ],
        modified_nodes: [],
        context_changes: %{added_mappings: %{}, removed_mappings: %{}, changed_mappings: %{}, base_changes: {nil, nil}},
        metadata: %{}
      }

      {:ok, is_valid} = Semantic.validate_patch(document, valid_diff)
      assert is_valid == true
    end

    test "rejects patches that remove non-existent triples" do
      document = %{
        "@context" => "http://schema.org/",
        "@id" => "http://example.com/person/1",
        "name" => "John Doe"
      }
      
      invalid_diff = %{
        added_triples: [],
        removed_triples: [
          %{
            subject: "http://example.com/person/1",
            predicate: "http://schema.org/age",
            object: "30"
          }
        ],
        modified_nodes: [],
        context_changes: %{added_mappings: %{}, removed_mappings: %{}, changed_mappings: %{}, base_changes: {nil, nil}},
        metadata: %{}
      }

      {:ok, is_valid} = Semantic.validate_patch(document, invalid_diff)
      assert is_valid == false
    end
  end

  describe "edge cases" do
    test "handles documents without @context" do
      old = %{"@id" => "http://example.com/1", "name" => "John"}
      new = %{"@id" => "http://example.com/1", "name" => "Jane"}

      {:ok, diff} = Semantic.diff(old, new)
      assert is_map(diff)
    end

    test "handles documents without @id" do
      old = %{"@context" => "http://schema.org/", "name" => "John"}
      new = %{"@context" => "http://schema.org/", "name" => "Jane"}

      {:ok, diff} = Semantic.diff(old, new)
      assert is_map(diff)
    end

    test "handles empty documents" do
      old = %{}
      new = %{"@context" => "http://schema.org/", "name" => "John"}

      {:ok, diff} = Semantic.diff(old, new)
      assert length(diff.added_triples) > 0 or length(diff.modified_nodes) > 0
    end

    test "handles identical documents" do
      doc = %{
        "@context" => "http://schema.org/",
        "@id" => "http://example.com/person/1", 
        "name" => "John Doe"
      }

      {:ok, diff} = Semantic.diff(doc, doc)
      
      # Should be recognized as semantically equivalent
      assert diff.metadata.semantic_equivalence == true
      assert length(diff.added_triples) == 0
      assert length(diff.removed_triples) == 0
    end
  end
end
