defmodule Mix.SpecApplyTest do
  use ExUnit.Case, async: false

  @req_id "test_apply"
  @root Path.expand(".")
  @work Path.join(@root, "work/spec_requests/#{@req_id}")
  @inbox Path.join(@work, "inbox")
  @patches Path.join(@work, "inbox/patches")
  @target_root Path.join(@root, "tmp_test/spec_apply")
  @target Path.join(@target_root, "target.json")

  setup do
    File.mkdir_p!(@patches)
    File.mkdir_p!(@target_root)
    # minimal request.json so tasks consider the request valid
    File.write!(Path.join(@work, "request.json"), ~s({"title":"stub"}))
    :ok
  end

  defp write_msg!(name, attachment_rel) do
    msg = %{
      "id" => name,
      "from" => %{"project" => "demo", "agent" => "tester"},
      "type" => "proposal",
      "ref" => %{"path" => @target, "json_pointer" => "/"},
      "body" => "apply patch",
      "attachments" => [attachment_rel],
      "relates_to" => %{"request_id" => @req_id},
      "status" => "open",
      "created_at" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    }
    File.write!(Path.join(@inbox, "msg_#{name}.json"), Jason.encode!(msg, pretty: true))
  end

  defp run_apply!(extra_args \\ []) do
    args = ["--id", @req_id, "--source", "inbox", "--target", @target_root] ++ extra_args
    Mix.Task.run("spec.apply", args)
  end

  test "RFC6902: add append '-'; copy and move" do
    File.write!(@target, ~s({"a":1,"arr":[0]}))
    patch = %{
      "file" => @target,
      "ops" => [
        %{"op" => "add", "path" => "/arr/-", "value" => 1},
        %{"op" => "copy", "from" => "/a", "path" => "/b"},
        %{"op" => "move", "from" => "/arr/0", "path" => "/arr/-"}
      ]
    }
    rel = "inbox/patches/patch_rfc6902.json"
    File.write!(Path.join(@work, rel), Jason.encode!(patch, pretty: true))
    write_msg!("0001", rel)

    run_apply!()

    out = Jason.decode!(File.read!(@target))
    assert out["b"] == 1
    assert out["arr"] == [1, 1]
  end

  test "replace-create and type change guard" do
    File.write!(@target, ~s({"obj":{"x":1}}))
    rel = "inbox/patches/patch_replace.json"

    # replace missing path should fail without --replace-create
    patch1 = %{"file" => @target, "ops" => [%{"op" => "replace", "path" => "/new/val", "value" => 5}]}
    File.write!(Path.join(@work, rel), Jason.encode!(patch1, pretty: true))
    write_msg!("0002", rel)
    assert_raise(RuntimeError, fn -> run_apply!() end)

    # with --replace-create it should add
    run_apply!(["--replace-create"])
    out = Jason.decode!(File.read!(@target))
    assert out["new"]["val"] == 5

    # replacing object with scalar should fail unless --allow-type-change
    patch2 = %{"file" => @target, "ops" => [%{"op" => "replace", "path" => "/obj", "value" => 3}]}
    File.write!(Path.join(@work, rel), Jason.encode!(patch2, pretty: true))
    assert_raise(RuntimeError, fn -> run_apply!() end)
    run_apply!(["--allow-type-change"])
    out2 = Jason.decode!(File.read!(@target))
    assert out2["obj"] == 3
  end

  test "baseline sha256 verification and force override" do
    File.write!(@target, ~s({"k":true}))
    content = File.read!(@target)
    good = :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)

    # Good baseline should pass
    patch_good = %{
      "file" => @target,
      "baseline_sha256" => good,
      "ops" => [%{"op" => "replace", "path" => "/k", "value" => false}]
    }
    rel = "inbox/patches/patch_baseline.json"
    File.write!(Path.join(@work, rel), Jason.encode!(patch_good, pretty: true))
    write_msg!("0003", rel)
    run_apply!()
    assert Jason.decode!(File.read!(@target))["k"] == false

    # Bad baseline should fail without --force
    patch_bad = %{"file" => @target, "baseline_sha256" => String.duplicate("0", 64), "ops" => [%{"op" => "replace", "path" => "/k", "value" => true}]}
    File.write!(Path.join(@work, rel), Jason.encode!(patch_bad, pretty: true))
    assert_raise(RuntimeError, fn -> run_apply!() end)

    # With --force it should apply
    run_apply!(["--force"])
    assert Jason.decode!(File.read!(@target))["k"] == true
  end

  test "format compact vs pretty" do
    File.write!(@target, ~s({"t":"x"}))
    rel = "inbox/patches/patch_fmt.json"
    patch = %{"file" => @target, "ops" => [%{"op" => "replace", "path" => "/t", "value" => "y"}]}
    File.write!(Path.join(@work, rel), Jason.encode!(patch, pretty: true))
    write_msg!("0004", rel)

    # Default compact output
    run_apply!()
    compact = File.read!(@target)
    refute String.contains?(compact, "\n")

    # Pretty output
    run_apply!(["--format", "pretty"])
    pretty = File.read!(@target)
    assert String.contains?(pretty, "\n  \"t\": \"y\"")
  end
end

