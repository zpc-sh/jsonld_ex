defmodule JsonldEx.C14nTest do
  use ExUnit.Case, async: true

  test "stable_json hash is deterministic and order-insensitive for maps" do
    a = %{b: 2, a: 1, c: [3, 2, 1]}
    b = %{"c" => [3, 2, 1], "b" => 2, "a" => 1}

    {:ok, h1} = JSONLD.hash(a, form: :stable_json)
    {:ok, h2} = JSONLD.hash(b, form: :stable_json)

    assert is_binary(h1.hash) and byte_size(h1.hash) == 64
    assert h1.hash == h2.hash
    assert h1.form == :stable_json
    assert h1.algorithm == :sha256
  end

  test "equal? respects canonical form" do
    x = %{"@id" => "ex:1", "name" => "Alice"}
    y = %{"name" => "Alice", "@id" => "ex:1"}
    assert JSONLD.equal?(x, y, form: :stable_json)
  end

  test "c14n returns nquads-like string (fallback ok)" do
    {:ok, %{nquads: nq}} = JSONLD.c14n(%{"@id" => "ex:1"})
    assert is_binary(nq)
    assert byte_size(nq) > 0
  end
end

