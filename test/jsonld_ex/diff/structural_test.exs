defmodule JsonldEx.Diff.StructuralTest do
  use ExUnit.Case, async: true

  alias JsonldEx.Diff.Structural

  describe "object diffing" do
    test "detects added properties" do
      old = %{"name" => "John"}
      new = %{"name" => "John", "age" => 30}

      {:ok, diff} = Structural.diff(old, new)
      assert diff["age"] == [30]
    end

    test "detects removed properties" do
      old = %{"name" => "John", "age" => 30}
      new = %{"name" => "John"}

      {:ok, diff} = Structural.diff(old, new)
      assert diff["age"] == [30, 0, 0]
    end

    test "detects changed properties" do
      old = %{"name" => "John", "age" => 30}
      new = %{"name" => "Jane", "age" => 30}

      {:ok, diff} = Structural.diff(old, new)
      assert diff["name"] == ["John", "Jane"]
    end

    test "handles nested objects" do
      old = %{"person" => %{"name" => "John", "age" => 30}}
      new = %{"person" => %{"name" => "Jane", "age" => 30, "city" => "NYC"}}

      {:ok, diff} = Structural.diff(old, new)
      assert diff["person"]["name"] == ["John", "Jane"]
      assert diff["person"]["city"] == ["NYC"]
    end

    test "no diff for identical objects" do
      doc = %{"name" => "John", "age" => 30}

      {:ok, diff} = Structural.diff(doc, doc)
      assert diff == %{}
    end
  end

  describe "array diffing" do
    test "detects array additions" do
      old = %{"items" => [1, 2]}
      new = %{"items" => [1, 2, 3]}

      {:ok, diff} = Structural.diff(old, new)
      assert diff["items"]["_2"] == [3]
    end

    test "detects array deletions" do
      old = %{"items" => [1, 2, 3]}
      new = %{"items" => [1, 2]}

      {:ok, diff} = Structural.diff(old, new)
      assert diff["items"]["_2"] == [3, 0, 0]
    end

    test "detects array changes" do
      old = %{"items" => [1, 2, 3]}
      new = %{"items" => [1, 4, 3]}

      {:ok, diff} = Structural.diff(old, new)
      assert diff["items"]["_1"] == [2, 4]
    end

    test "detects array moves when enabled" do
      old = %{"items" => ["a", "b", "c"]}
      new = %{"items" => ["b", "a", "c"]}

      {:ok, diff} = Structural.diff(old, new, include_moves: true)
      
      # Should detect that "b" moved from position 1 to position 0
      assert Map.has_key?(diff["items"], "_0")
      move_op = diff["items"]["_0"]
      assert match?(["", 1, 3], move_op)
    end

    test "simple array diff when moves disabled" do
      old = %{"items" => ["a", "b", "c"]}
      new = %{"items" => ["b", "a", "c"]}

      {:ok, diff} = Structural.diff(old, new, include_moves: false)
      
      # Should treat as changes rather than moves
      assert diff["items"]["_0"] == ["a", "b"]
      assert diff["items"]["_1"] == ["b", "a"]
    end
  end

  describe "text diffing" do
    test "uses text diff for long strings" do
      old = %{"description" => String.duplicate("This is a long description that should trigger text diffing. ", 10)}
      new = %{"description" => String.duplicate("This is a modified long description that should trigger text diffing. ", 10)}

      {:ok, diff} = Structural.diff(old, new, text_diff: true)
      
      # Should create text diff format [text_diff, 0, 2]
      text_diff = diff["description"]
      assert is_list(text_diff) and length(text_diff) == 3
      assert Enum.at(text_diff, 1) == 0
      assert Enum.at(text_diff, 2) == 2
    end

    test "uses simple diff for short strings" do
      old = %{"name" => "John"}
      new = %{"name" => "Jane"}

      {:ok, diff} = Structural.diff(old, new, text_diff: true)
      assert diff["name"] == ["John", "Jane"]
    end

    test "disables text diff when option is false" do
      old = %{"description" => String.duplicate("Long text ", 50)}
      new = %{"description" => String.duplicate("Modified long text ", 50)}

      {:ok, diff} = Structural.diff(old, new, text_diff: false)
      assert match?([_old, _new], diff["description"])
    end
  end

  describe "patching" do
    test "applies additions" do
      document = %{"name" => "John"}
      patch = %{"age" => [30]}

      {:ok, result} = Structural.patch(document, patch)
      assert result["age"] == 30
    end

    test "applies deletions" do
      document = %{"name" => "John", "age" => 30}
      patch = %{"age" => [30, 0, 0]}

      {:ok, result} = Structural.patch(document, patch)
      assert Map.get(result, "age") == nil
    end

    test "applies changes" do
      document = %{"name" => "John", "age" => 30}
      patch = %{"name" => ["John", "Jane"], "age" => [30, 31]}

      {:ok, result} = Structural.patch(document, patch)
      assert result["name"] == "Jane"
      assert result["age"] == 31
    end

    test "applies nested patches" do
      document = %{"person" => %{"name" => "John", "age" => 30}}
      patch = %{"person" => %{"name" => ["John", "Jane"], "city" => ["NYC"]}}

      {:ok, result} = Structural.patch(document, patch)
      assert result["person"]["name"] == "Jane"
      assert result["person"]["city"] == "NYC"
    end

    test "applies array patches" do
      document = %{"items" => [1, 2, 3]}
      patch = %{"items" => %{"_1" => [2, 4], "_3" => [5]}}

      {:ok, result} = Structural.patch(document, patch)
      assert result["items"] == [1, 4, 3, 5]
    end

    test "applies text diff patches" do
      old_text = String.duplicate("Long text ", 50)
      new_text = String.duplicate("Modified long text ", 50)
      old = %{"description" => old_text}
      new = %{"description" => new_text}

      {:ok, diff} = Structural.diff(old, new, text_diff: true)
      {:ok, patched} = Structural.patch(old, diff)

      assert patched["description"] == new_text
    end
  end

  describe "merge and inverse" do
    test "merges simple diffs" do
      diff1 = %{"name" => ["John", "Jane"]}
      diff2 = %{"age" => [30]}

      {:ok, merged} = Structural.merge_diffs([diff1, diff2])
      assert merged["name"] == ["John", "Jane"]
      assert merged["age"] == [30]
    end

    test "later diffs override earlier ones" do
      diff1 = %{"name" => ["John", "Jane"]}
      diff2 = %{"name" => ["John", "Bob"]}

      {:ok, merged} = Structural.merge_diffs([diff1, diff2])
      assert merged["name"] == ["John", "Bob"]
    end

    test "generates inverse diff" do
      diff = %{
        "name" => ["John", "Jane"],
        "age" => [30],
        "city" => ["NYC", 0, 0]
      }

      {:ok, inverse} = Structural.inverse(diff)
      assert inverse["name"] == ["Jane", "John"]
      assert inverse["age"] == [30, 0, 0]
      assert inverse["city"] == ["NYC"]
    end
  end

  describe "validation" do
    test "validates correct patches" do
      document = %{"name" => "John", "age" => 30}
      patch = %{"name" => ["John", "Jane"]}

      {:ok, valid} = Structural.validate_patch(document, patch)
      assert valid == true
    end

    test "rejects invalid patches" do
      document = %{"name" => "John"}
      # This patch would try to change a non-existent property
      patch = %{"age" => [25, 30]}

      {:ok, valid} = Structural.validate_patch(document, patch)
      assert valid == false
    end
  end

  describe "edge cases" do
    test "handles nil values" do
      old = %{"value" => nil}
      new = %{"value" => "something"}

      {:ok, diff} = Structural.diff(old, new)
      assert diff["value"] == [nil, "something"]
    end

    test "handles empty objects" do
      old = %{}
      new = %{"name" => "John"}

      {:ok, diff} = Structural.diff(old, new)
      assert diff["name"] == ["John"]
    end

    test "handles empty arrays" do
      old = %{"items" => []}
      new = %{"items" => [1, 2]}

      {:ok, diff} = Structural.diff(old, new)
      assert diff["items"]["_0"] == [1]
      assert diff["items"]["_1"] == [2]
    end

    test "handles mixed types" do
      old = %{"value" => "string"}
      new = %{"value" => 42}

      {:ok, diff} = Structural.diff(old, new)
      assert diff["value"] == ["string", 42]
    end
  end
end
