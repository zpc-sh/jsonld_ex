defmodule JsonldEx.Diff.OperationalTest do
  use ExUnit.Case, async: true

  alias JsonldEx.Diff.Operational

  describe "operational diff generation" do
    test "generates set operations for changed values" do
      old = %{"name" => "John", "age" => 30}
      new = %{"name" => "Jane", "age" => 30}

      {:ok, diff} = Operational.diff(old, new)
      
      assert is_list(diff.operations)
      
      set_ops = Enum.filter(diff.operations, &(&1.type == :set))
      assert length(set_ops) == 1
      
      name_op = Enum.find(set_ops, &(&1.path == ["name"]))
      assert name_op.value == "Jane"
    end

    test "generates delete operations for removed properties" do
      old = %{"name" => "John", "age" => 30, "city" => "NYC"}
      new = %{"name" => "John", "age" => 30}

      {:ok, diff} = Operational.diff(old, new)
      
      delete_ops = Enum.filter(diff.operations, &(&1.type == :delete))
      assert length(delete_ops) == 1
      
      city_op = Enum.find(delete_ops, &(&1.path == ["city"]))
      assert city_op != nil
    end

    test "generates operations with timestamps and actor IDs" do
      old = %{"name" => "John"}
      new = %{"name" => "Jane"}

      {:ok, diff} = Operational.diff(old, new, actor_id: "test_actor")
      
      assert length(diff.operations) > 0
      op = hd(diff.operations)
      assert op.actor_id == "test_actor"
      assert is_integer(op.timestamp)
    end

    test "includes metadata" do
      old = %{"name" => "John"}
      new = %{"name" => "Jane"}

      {:ok, diff} = Operational.diff(old, new, actor_id: "test_actor")
      
      assert diff.metadata.actors == ["test_actor"]
      assert diff.metadata.conflict_resolution == :last_write_wins
      assert is_tuple(diff.metadata.timestamp_range)
    end

    test "handles nested objects" do
      old = %{"person" => %{"name" => "John", "age" => 30}}
      new = %{"person" => %{"name" => "Jane", "age" => 31}}

      {:ok, diff} = Operational.diff(old, new)
      
      set_ops = Enum.filter(diff.operations, &(&1.type == :set))
      
      name_op = Enum.find(set_ops, &(&1.path == ["person", "name"]))
      age_op = Enum.find(set_ops, &(&1.path == ["person", "age"]))
      
      assert name_op.value == "Jane"
      assert age_op.value == 31
    end

    test "handles arrays with insert/delete operations" do
      old = %{"items" => [1, 2, 3]}
      new = %{"items" => [1, 4, 3, 5]}

      {:ok, diff} = Operational.diff(old, new)
      
      # Should have delete operations to clear array and insert operations to rebuild
      delete_ops = Enum.filter(diff.operations, &(&1.type == :delete))
      insert_ops = Enum.filter(diff.operations, &(&1.type == :insert))
      
      assert length(delete_ops) > 0
      assert length(insert_ops) > 0
    end

    test "generates move operations for reordered arrays" do
      old = %{"items" => ["a", "b", "c"]}
      new = %{"items" => ["b", "a", "c"]}

      {:ok, diff} = Operational.diff(old, new)

      move_ops = Enum.filter(diff.operations, &(&1.type == :move))
      assert length(move_ops) > 0

      # Expect at least one move from index 1 to index 0 within "items"
      assert Enum.any?(move_ops, fn op -> op.path == ["items", 0] and op.from == 1 end)

      # Patching should yield the new document
      {:ok, patched} = Operational.patch(old, diff)
      assert patched == new
    end

    test "generates move operations for forward moves" do
      old = %{"items" => ["a", "b", "c", "d"]}
      new = %{"items" => ["a", "c", "b", "d"]}

      {:ok, diff} = Operational.diff(old, new)
      move_ops = Enum.filter(diff.operations, &(&1.type == :move))
      assert length(move_ops) > 0

      # Expect a move of "c" from index 2 to index 1
      assert Enum.any?(move_ops, fn op -> op.path == ["items", 1] and op.from == 2 end)

      {:ok, patched} = Operational.patch(old, diff)
      assert patched == new
    end
  end

  describe "operational patching" do
    test "applies set operations" do
      document = %{"name" => "John", "age" => 30}
      
      operations = [
        %{type: :set, path: ["name"], value: "Jane", timestamp: 1, actor_id: "test"}
      ]
      
      diff = %{operations: operations, metadata: %{}}

      {:ok, result} = Operational.patch(document, diff)
      assert result["name"] == "Jane"
      assert result["age"] == 30
    end

    test "applies delete operations" do
      document = %{"name" => "John", "age" => 30, "city" => "NYC"}
      
      operations = [
        %{type: :delete, path: ["city"], value: nil, timestamp: 1, actor_id: "test"}
      ]
      
      diff = %{operations: operations, metadata: %{}}

      {:ok, result} = Operational.patch(document, diff)
      assert result["name"] == "John"
      assert result["age"] == 30
      assert Map.get(result, "city") == nil
    end

    test "applies insert operations" do
      document = %{"name" => "John"}
      
      operations = [
        %{type: :insert, path: ["age"], value: 30, timestamp: 1, actor_id: "test"}
      ]
      
      diff = %{operations: operations, metadata: %{}}

      {:ok, result} = Operational.patch(document, diff)
      assert result["name"] == "John"
      assert result["age"] == 30
    end

    test "applies operations in timestamp order" do
      document = %{"counter" => 0}
      
      operations = [
        %{type: :set, path: ["counter"], value: 2, timestamp: 2, actor_id: "test2"},
        %{type: :set, path: ["counter"], value: 1, timestamp: 1, actor_id: "test1"}
      ]
      
      diff = %{operations: operations, metadata: %{}}

      {:ok, result} = Operational.patch(document, diff)
      # Later timestamp should win
      assert result["counter"] == 2
    end
  end

  describe "diff merging" do
    test "merges operations from different actors" do
      diff1 = %{
        operations: [
          %{type: :set, path: ["name"], value: "Jane", timestamp: 1, actor_id: "actor1"}
        ],
        metadata: %{actors: ["actor1"], conflict_resolution: :last_write_wins}
      }
      
      diff2 = %{
        operations: [
          %{type: :set, path: ["age"], value: 31, timestamp: 2, actor_id: "actor2"}
        ],
        metadata: %{actors: ["actor2"], conflict_resolution: :last_write_wins}
      }

      {:ok, merged} = Operational.merge_diffs([diff1, diff2])
      
      assert length(merged.operations) == 2
      assert Enum.any?(merged.operations, &(&1.path == ["name"] and &1.actor_id == "actor1"))
      assert Enum.any?(merged.operations, &(&1.path == ["age"] and &1.actor_id == "actor2"))
      assert merged.metadata.actors == ["actor1", "actor2"]
    end

    test "resolves conflicts with last_write_wins" do
      diff1 = %{
        operations: [
          %{type: :set, path: ["name"], value: "Jane", timestamp: 1, actor_id: "actor1"}
        ],
        metadata: %{actors: ["actor1"], conflict_resolution: :last_write_wins}
      }
      
      diff2 = %{
        operations: [
          %{type: :set, path: ["name"], value: "Bob", timestamp: 2, actor_id: "actor2"}
        ],
        metadata: %{actors: ["actor2"], conflict_resolution: :last_write_wins}
      }

      {:ok, merged} = Operational.merge_diffs([diff1, diff2], conflict_resolution: :last_write_wins)
      
      # Should only have the operation with later timestamp
      name_ops = Enum.filter(merged.operations, &(&1.path == ["name"]))
      assert length(name_ops) == 1
      assert hd(name_ops).value == "Bob"
      assert hd(name_ops).timestamp == 2
    end

    test "preserves all operations with merge strategy" do
      diff1 = %{
        operations: [
          %{type: :set, path: ["name"], value: "Jane", timestamp: 1, actor_id: "actor1"}
        ],
        metadata: %{actors: ["actor1"], conflict_resolution: :merge}
      }
      
      diff2 = %{
        operations: [
          %{type: :set, path: ["name"], value: "Bob", timestamp: 2, actor_id: "actor2"}
        ],
        metadata: %{actors: ["actor2"], conflict_resolution: :merge}
      }

      {:ok, merged} = Operational.merge_diffs([diff1, diff2], conflict_resolution: :merge)
      
      # Should preserve all operations when using merge strategy
      assert length(merged.operations) == 2
    end
  end

  describe "inverse operations" do
    test "inverts set operations to delete operations" do
      diff = %{
        operations: [
          %{type: :set, path: ["name"], value: "Jane", timestamp: 1, actor_id: "test"}
        ],
        metadata: %{conflict_resolution: :last_write_wins}
      }

      {:ok, inverse} = Operational.inverse(diff)
      
      assert length(inverse.operations) == 1
      op = hd(inverse.operations)
      assert op.type == :delete
      assert op.path == ["name"]
    end

    test "inverts delete operations to set operations" do
      diff = %{
        operations: [
          %{type: :delete, path: ["age"], value: nil, timestamp: 1, actor_id: "test"}
        ],
        metadata: %{conflict_resolution: :last_write_wins}
      }

      {:ok, inverse} = Operational.inverse(diff)
      
      assert length(inverse.operations) == 1
      op = hd(inverse.operations)
      assert op.type == :set
      assert op.path == ["age"]
    end

    test "reverses operation order" do
      operations = [
        %{type: :set, path: ["name"], value: "Jane", timestamp: 1, actor_id: "test"},
        %{type: :set, path: ["age"], value: 30, timestamp: 2, actor_id: "test"}
      ]
      
      diff = %{operations: operations, metadata: %{}}

      {:ok, inverse} = Operational.inverse(diff)
      
      # Operations should be in reverse order
      assert length(inverse.operations) == 2
      assert hd(inverse.operations).path == ["age"]
      assert Enum.at(inverse.operations, 1).path == ["name"]
    end
  end

  describe "validation" do
    test "validates operations against document" do
      document = %{"name" => "John", "age" => 30}
      
      valid_diff = %{
        operations: [
          %{type: :set, path: ["name"], value: "Jane", timestamp: 1, actor_id: "test"}
        ],
        metadata: %{}
      }

      {:ok, is_valid} = Operational.validate_patch(document, valid_diff)
      assert is_valid == true
    end

    test "rejects operations on non-existent paths" do
      document = %{"name" => "John"}
      
      invalid_diff = %{
        operations: [
          %{type: :delete, path: ["age"], value: nil, timestamp: 1, actor_id: "test"}
        ],
        metadata: %{}
      }

      {:ok, is_valid} = Operational.validate_patch(document, invalid_diff)
      assert is_valid == false
    end
  end

  describe "edge cases" do
    test "handles empty operations list" do
      diff = %{operations: [], metadata: %{}}
      document = %{"name" => "John"}

      {:ok, result} = Operational.patch(document, diff)
      assert result == document
    end

    test "generates unique actor IDs when not provided" do
      old = %{"name" => "John"}
      new = %{"name" => "Jane"}

      {:ok, diff1} = Operational.diff(old, new)
      {:ok, diff2} = Operational.diff(old, new)
      
      # Should have different actor IDs
      actor1 = diff1.metadata.actors |> hd()
      actor2 = diff2.metadata.actors |> hd()
      
      assert actor1 != actor2
    end

    test "handles complex nested structures" do
      old = %{
        "user" => %{
          "profile" => %{
            "name" => "John",
            "settings" => %{
              "theme" => "dark"
            }
          }
        }
      }
      
      new = %{
        "user" => %{
          "profile" => %{
            "name" => "Jane",
            "settings" => %{
              "theme" => "light",
              "notifications" => true
            }
          }
        }
      }

      {:ok, diff} = Operational.diff(old, new)
      {:ok, result} = Operational.patch(old, diff)
      
      assert result["user"]["profile"]["name"] == "Jane"
      assert result["user"]["profile"]["settings"]["theme"] == "light"
      assert result["user"]["profile"]["settings"]["notifications"] == true
    end
  end
end
