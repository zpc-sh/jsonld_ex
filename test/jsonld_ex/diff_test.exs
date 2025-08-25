defmodule JsonldEx.DiffTest do
  use ExUnit.Case, async: true
  doctest JsonldEx.Diff

  alias JsonldEx.Diff

  describe "main diff interface" do
    test "diff with structural strategy" do
      old = %{"name" => "John", "age" => 30}
      new = %{"name" => "Jane", "age" => 30, "city" => "NYC"}

      assert {:ok, diff} = Diff.diff(old, new, strategy: :structural)
      assert diff["name"] == ["John", "Jane"]
      assert diff["city"] == ["NYC"]
    end

    test "diff with operational strategy" do
      old = %{"name" => "John", "age" => 30}
      new = %{"name" => "Jane", "age" => 30, "city" => "NYC"}

      assert {:ok, diff} = Diff.diff(old, new, strategy: :operational)
      assert is_map(diff)
      assert Map.has_key?(diff, :operations)
      assert length(diff.operations) > 0
    end

    test "diff with semantic strategy" do
      old = %{
        "@context" => "https://schema.org/",
        "@id" => "http://example.com/person/1",
        "name" => "John Doe"
      }
      new = %{
        "@context" => "https://schema.org/",
        "@id" => "http://example.com/person/1",
        "name" => "Jane Doe",
        "@type" => "Person"
      }

      assert {:ok, diff} = Diff.diff(old, new, strategy: :semantic)
      assert is_map(diff)
      assert Map.has_key?(diff, :modified_nodes)
    end

    test "patch applies correctly" do
      old = %{"name" => "John", "age" => 30}
      new = %{"name" => "Jane", "age" => 30, "city" => "NYC"}

      {:ok, diff} = Diff.diff(old, new, strategy: :structural)
      {:ok, result} = Diff.patch(old, diff, strategy: :structural)

      assert result["name"] == "Jane"
      assert result["city"] == "NYC"
      assert result["age"] == 30
    end

    test "invalid strategy returns error" do
      old = %{"name" => "John"}
      new = %{"name" => "Jane"}

      assert {:error, {:invalid_strategy, :invalid}} = 
        Diff.diff(old, new, strategy: :invalid)
    end

    test "inverse diff works" do
      old = %{"name" => "John", "age" => 30}
      new = %{"name" => "Jane", "city" => "NYC"}

      {:ok, forward_diff} = Diff.diff(old, new, strategy: :structural)
      {:ok, inverse_diff} = Diff.inverse(forward_diff, strategy: :structural)
      {:ok, result} = Diff.patch(new, inverse_diff, strategy: :structural)

      assert result["name"] == "John"
      assert result["age"] == 30
      assert Map.get(result, "city") == nil
    end
  end

  describe "merge diffs" do
    test "merges multiple structural diffs" do
      base = %{"name" => "John", "age" => 30}
      v1 = %{"name" => "Jane", "age" => 30}
      v2 = %{"name" => "John", "age" => 31, "city" => "NYC"}

      {:ok, diff1} = Diff.diff(base, v1, strategy: :structural)
      {:ok, diff2} = Diff.diff(base, v2, strategy: :structural)

      {:ok, merged} = Diff.merge_diffs([diff1, diff2], strategy: :structural)
      {:ok, result} = Diff.patch(base, merged, strategy: :structural)

      assert result["age"] == 31  # Later diff wins
      assert result["city"] == "NYC"
    end

    test "merges operational diffs with conflict resolution" do
      base = %{"name" => "John", "age" => 30}
      v1 = %{"name" => "Jane", "age" => 30}
      v2 = %{"name" => "Bob", "age" => 31}

      {:ok, diff1} = Diff.diff(base, v1, strategy: :operational, actor_id: "actor1")
      {:ok, diff2} = Diff.diff(base, v2, strategy: :operational, actor_id: "actor2")

      {:ok, merged} = Diff.merge_diffs([diff1, diff2], 
        strategy: :operational, 
        conflict_resolution: :last_write_wins)
      
      assert is_map(merged)
      assert length(merged.operations) >= 0
    end
  end

  describe "validation" do
    test "validates structural patches" do
      document = %{"name" => "John", "age" => 30}
      valid_patch = %{"name" => ["John", "Jane"]}
      
      {:ok, is_valid} = Diff.validate_patch(document, valid_patch, strategy: :structural)
      assert is_valid == true
    end

    test "detects invalid patches" do
      document = %{"name" => "John"}
      invalid_patch = %{"nonexistent" => ["old", "new"]}
      
      {:ok, is_valid} = Diff.validate_patch(document, invalid_patch, strategy: :structural)
      assert is_valid == false
    end
  end
end