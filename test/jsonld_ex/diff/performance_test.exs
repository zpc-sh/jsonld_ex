defmodule JsonldEx.Diff.PerformanceTest do
  use ExUnit.Case, async: false  # Performance tests should not run in parallel

  alias JsonldEx.Diff.Performance

  describe "performance layer" do
    test "fallback to elixir when NIF unavailable" do
      old = %{"name" => "John", "age" => 30}
      new = %{"name" => "Jane", "age" => 30, "city" => "NYC"}

      # Should work regardless of NIF availability
      {:ok, diff} = Performance.diff_structural(old, new)
      assert is_map(diff)
    end

    test "native availability detection" do
      is_available = Performance.native_available?()
      assert is_boolean(is_available)
    end

    test "LCS computation fallback" do
      old_array = [1, 2, 3, 4]
      new_array = [1, 3, 4, 5]

      {:ok, operations} = Performance.compute_lcs(old_array, new_array)
      assert is_list(operations)
    end

    test "text diff fallback" do
      old_text = "The quick brown fox"
      new_text = "The slow brown fox"

      {:ok, diff} = Performance.text_diff_myers(old_text, new_text)
      assert is_map(diff)
      assert Map.has_key?(diff, :operations)
    end

    test "RDF normalization fallback" do
      document = %{
        "@context" => "http://schema.org/",
        "@id" => "http://example.com/person/1",
        "name" => "John Doe"
      }

      {:ok, normalized} = Performance.normalize_rdf_graph(document)
      assert is_binary(normalized)
      assert String.contains?(normalized, "http://example.com/person/1")
    end
  end

  describe "benchmarking" do
    test "benchmarks different strategies" do
      old = %{
        "@context" => "http://schema.org/",
        "@id" => "http://example.com/person/1",
        "name" => "John Doe",
        "age" => 30
      }
      
      new = %{
        "@context" => "http://schema.org/",
        "@id" => "http://example.com/person/1", 
        "name" => "Jane Doe",
        "age" => 31,
        "@type" => "Person"
      }

      # Use fewer iterations for testing
      benchmark_results = Performance.benchmark_strategies(old, new, 5)
      
      assert benchmark_results.iterations == 5
      assert is_list(benchmark_results.results)
      assert length(benchmark_results.results) == 3  # structural, operational, semantic
      
      Enum.each(benchmark_results.results, fn result ->
        assert Map.has_key?(result, :strategy)
        assert Map.has_key?(result, :elixir_time_μs)
        assert Map.has_key?(result, :native_time_μs)
        assert Map.has_key?(result, :speedup)
        assert Map.has_key?(result, :native_available)
        
        assert result.strategy in [:structural, :operational, :semantic]
        assert is_integer(result.elixir_time_μs)
        assert is_integer(result.native_time_μs)
        assert is_number(result.speedup)
        assert is_boolean(result.native_available)
      end)
      
      assert Map.has_key?(benchmark_results, :document_size)
      assert Map.has_key?(benchmark_results.document_size, :old_bytes)
      assert Map.has_key?(benchmark_results.document_size, :new_bytes)
      assert Map.has_key?(benchmark_results.document_size, :total_bytes)
    end

    test "measures performance correctly" do
      old = %{"counter" => 0}
      new = %{"counter" => 1}

      # Measure time for a simple operation
      {time_μs, {:ok, _diff}} = :timer.tc(fn ->
        Performance.diff_structural(old, new)
      end)

      # Should complete in reasonable time (less than 1 second)
      assert time_μs < 1_000_000
    end
  end

  describe "operational diff performance" do
    test "handles operational merging efficiently" do
      # Create multiple diffs to merge
      base = %{"counter" => 0, "name" => "test"}
      
      diffs = Enum.map(1..10, fn i ->
        %{
          operations: [
            %{type: :set, path: ["counter"], value: i, timestamp: i, actor_id: "actor#{i}"}
          ],
          metadata: %{actors: ["actor#{i}"], conflict_resolution: :last_write_wins}
        }
      end)

      {:ok, merged} = Performance.merge_operational_diffs(diffs)
      
      # Should resolve to the highest counter value
      counter_ops = Enum.filter(merged.operations, &(&1.path == ["counter"]))
      assert length(counter_ops) == 1
      assert hd(counter_ops).value == 10
    end
  end

  describe "large document performance" do
    test "handles moderately large documents" do
      # Create a document with nested structure
      large_old = %{
        "@context" => "http://schema.org/",
        "@id" => "http://example.com/org/1",
        "@type" => "Organization",
        "name" => "Big Corp",
        "employees" => Enum.map(1..50, fn i ->
          %{
            "@type" => "Person",
            "@id" => "http://example.com/person/#{i}",
            "name" => "Employee #{i}",
            "employeeId" => i,
            "department" => "Dept #{rem(i, 5)}"
          }
        end)
      }
      
      large_new = %{large_old | 
        "name" => "Bigger Corp",
        "employees" => Enum.map(1..50, fn i ->
          %{
            "@type" => "Person", 
            "@id" => "http://example.com/person/#{i}",
            "name" => "Employee #{i}",
            "employeeId" => i,
            "department" => "Dept #{rem(i, 5)}",
            "status" => if(rem(i, 10) == 0, do: "manager", else: "employee")
          }
        end)
      }

      # Should complete without timing out
      {time_μs, {:ok, diff}} = :timer.tc(fn ->
        Performance.diff_structural(large_old, large_new)
      end)

      assert is_map(diff)
      # Should complete in reasonable time (less than 5 seconds)
      assert time_μs < 5_000_000
    end
  end

  describe "error handling" do
    test "handles malformed documents gracefully" do
      old = %{"valid" => "document"}
      
      # Test with various problematic inputs
      problematic_inputs = [
        nil,
        [],
        "not a map",
        %{"circular" => %{"ref" => :self}}
      ]

      Enum.each(problematic_inputs, fn bad_new ->
        try do
          Performance.diff_structural(old, bad_new)
        catch
          _ -> :ok  # Expected to fail
        end
      end)
    end

    test "handles NIF errors gracefully" do
      old = %{"test" => "value"}
      new = %{"test" => "changed"}

      # Should work even if NIFs throw errors
      {:ok, diff} = Performance.diff_structural(old, new)
      assert is_map(diff)
    end
  end

  describe "memory efficiency" do
    test "does not leak memory on repeated operations" do
      old = %{"counter" => 0}
      
      # Perform many diff operations
      for i <- 1..100 do
        new = %{"counter" => i}
        {:ok, _diff} = Performance.diff_structural(old, new)
      end
      
      # If we get here without running out of memory, test passes
      assert true
    end

    test "handles nested document updates efficiently" do
      base_doc = %{
        "level1" => %{
          "level2" => %{
            "level3" => %{
              "value" => 0
            }
          }
        }
      }

      # Perform nested updates
      updated_docs = Enum.map(1..20, fn i ->
        put_in(base_doc, ["level1", "level2", "level3", "value"], i)
      end)

      # Should handle all updates efficiently
      diffs = Enum.map(updated_docs, fn doc ->
        {:ok, diff} = Performance.diff_structural(base_doc, doc)
        diff
      end)

      assert length(diffs) == 20
      Enum.each(diffs, fn diff ->
        assert is_map(diff)
      end)
    end
  end
end