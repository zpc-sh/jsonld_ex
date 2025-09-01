defmodule Mix.Tasks.Spec.Apply do
  use Mix.Task
  @shortdoc "Apply proposal patch.json attachments from messages to target files"
  @moduledoc """
  Usage:
    mix spec.apply --id <request_id> \
      [--source inbox|outbox] \
      [--target /path/to/target/repo] \
      [--dry-run] [--force] [--diff] \
      [--baseline-rev <git_rev>] [--summary-json] \
      [--replace-create] [--allow-type-change]

  Scans messages of type "proposal" under the chosen source (default: inbox),
  finds attachments named `patch.json`, and applies JSON Pointer operations
  (add/replace/remove) to the referenced file(s).

  Patch format (either inline file or via message ref):
  {
    "file": "relative/path.json",         # optional; falls back to message.ref.path
    "base_pointer": "/api",               # optional; falls back to message.ref.json_pointer
    "ops": [
      {"op": "replace", "path": "/hash", "value": "..."},
      {"op": "add",     "path": "/foo/bar", "value": 1},
      {"op": "remove",  "path": "/old"}
    ]
  }
  """

  @impl true
  def run(argv) do
    {opts, _, _} = OptionParser.parse(argv, switches: [
      id: :string,
      source: :string,
      target: :string,
      dry_run: :boolean,
      force: :boolean,
      diff: :boolean,
      baseline_rev: :string,
      summary_json: :boolean,
      replace_create: :boolean,
      allow_type_change: :boolean
    ])
    id = req!(opts, :id)
    source = Keyword.get(opts, :source, "inbox")
    target_root = Keyword.get(opts, :target, File.cwd!())
    dry_run = Keyword.get(opts, :dry_run, false)
    force = Keyword.get(opts, :force, false)
    show_diff = Keyword.get(opts, :diff, false)
    baseline_rev_opt = Keyword.get(opts, :baseline_rev, nil)
    summary_json? = Keyword.get(opts, :summary_json, false)
    replace_create? = Keyword.get(opts, :replace_create, false)
    allow_type_change? = Keyword.get(opts, :allow_type_change, false)

    req_root = Path.join(["work", "spec_requests", id])
    src_dir = Path.join(req_root, source)
    File.dir?(src_dir) || Mix.raise("Source not found: #{src_dir}")

    messages = Path.wildcard(Path.join(src_dir, "msg_*.json"))
    |> Enum.map(&{&1, Jason.decode!(File.read!(&1))})
    |> Enum.filter(fn {_p, m} -> m["type"] == "proposal" end)

    results =
      if messages == [] do
        Mix.shell().info("No proposal messages found in #{src_dir}")
        []
      else
        Enum.reduce(messages, [], fn {msg_path, msg}, acc ->
          (msg["attachments"] || [])
          |> Enum.filter(&String.ends_with?(&1, "patch.json"))
          |> Enum.reduce(acc, fn rel, acc2 ->
            patch_path = Path.join(req_root, rel)
            result = apply_patch!(patch_path, msg, target_root, dry_run, force, show_diff, id, baseline_rev_opt, replace_create?, allow_type_change?)
            info = case result do
              {:ok, info} when dry_run ->
                Mix.shell().info("[DRY-RUN] Would apply #{length(info.paths)} ops to #{info.file} (baseline_ok=#{info.baseline_ok}, baseline_git_ok=#{info.baseline_git_ok})")
                if show_diff, do: print_diff_preview(info)
                info
              {:ok, info} ->
                Mix.shell().info("Applied #{length(info.paths)} ops to #{info.file} (baseline_ok=#{info.baseline_ok}, baseline_git_ok=#{info.baseline_git_ok}) from #{rel} (msg #{Path.basename(msg_path)})")
                if show_diff, do: print_diff_preview(info)
                info
            end
            acc2 ++ [Map.merge(info, %{message: Path.basename(msg_path), patch: rel, dry_run: dry_run})]
          end)
        end)
      end

    if summary_json? do
      summary = %{
        id: id,
        source: source,
        target_root: target_root,
        results: results
      }
      Mix.shell().info(Jason.encode!(summary, pretty: true))
    end

    :ok
  end

  defp apply_patch!(patch_path, msg, target_root, dry_run, force, show_diff, id, baseline_rev_opt, replace_create?, allow_type_change?) do
    patch = Jason.decode!(File.read!(patch_path))
    file_rel = patch["file"] || get_in(msg, ["ref", "path"]) || Mix.raise("Patch missing file and message.ref.path")
    base_ptr = patch["base_pointer"] || get_in(msg, ["ref", "json_pointer"]) || ""
    ops = patch["ops"] || Mix.raise("Patch missing ops")

    target_path = Path.join(target_root, file_rel)
    content = File.read!(target_path)
    json = Jason.decode!(content)

    # Baseline check via optional hash in patch
    baseline_ok =
      case {patch["baseline_sha256"], patch["baseline_sha1"]} do
        {nil, nil} -> true
        {hex, nil} -> compare_hash(:sha256, content, hex)
        {nil, hex} -> compare_hash(:sha, content, hex)
        {hex256, _} -> compare_hash(:sha256, content, hex256)
      end

    # Optional git-based baseline comparison
    baseline_rev = patch["baseline_git_rev"] || baseline_rev_opt
    baseline_git_ok =
      case baseline_rev do
        nil -> true
        rev when is_binary(rev) ->
          case git_show_file(target_root, rev, file_rel) do
            {:ok, baseline_content} -> baseline_content == content
            {:error, _} -> false
          end
      end

    # Also compute hash comparison against the git baseline (detect any content change)
    baseline_git_hash_ok =
      case baseline_rev do
        nil -> true
        rev when is_binary(rev) ->
          case git_show_file(target_root, rev, file_rel) do
            {:ok, baseline_content} ->
              compare_hash(:sha256, baseline_content, :crypto.hash(:sha256, content) |> Base.encode16(case: :lower))
            {:error, _} -> false
          end
      end

    if (not baseline_ok or not baseline_git_ok or not baseline_git_hash_ok) and not force do
      Mix.raise("Baseline mismatch for #{file_rel} (hash_ok=#{baseline_ok}, git_eq=#{baseline_git_ok}, git_hash=#{baseline_git_hash_ok}). Use --force to override.")
    end

    {final, applied_paths} =
      Enum.reduce(ops, {json, []}, fn op, {acc, paths} ->
        ptr = normalize_ptr(base_ptr, Map.fetch!(op, "path"))
        # Existence checks for replace/remove
        case op["op"] do
          "replace" ->
            cond do
              pointer_exists?(acc, ptr) -> :ok
              replace_create? -> :ok
              true -> Mix.raise("Pointer not found for replace: #{ptr}")
            end
          "remove" -> if not pointer_exists?(acc, ptr), do: Mix.raise("Pointer not found for remove: #{ptr}")
          _ -> :ok
        end
        # Type check: prevent replacing object/array with scalar (and vice versa) unless allowed
        effective_op =
          cond do
            op["op"] == "replace" and pointer_exists?(acc, ptr) and not allow_type_change? ->
              case get_in_pointer(acc, pointer_tokens(ptr)) do
                {:ok, current} ->
                  v = Map.get(op, "value")
                  if type_tag(current) == type_tag(v), do: op, else: Mix.raise("Type change not allowed at #{ptr}: #{type_tag(current)} -> #{type_tag(v)}")
                :error -> op
              end
            op["op"] == "replace" and not pointer_exists?(acc, ptr) and replace_create? -> Map.put(op, "op", "add")
            true -> op
          end
        {apply_op!(acc, base_ptr, effective_op), paths ++ [ptr]}
      end)

    before_pretty = Jason.encode!(json, pretty: true)
    after_pretty = Jason.encode!(final, pretty: true)

    info = %{file: file_rel, baseline_ok: baseline_ok, baseline_git_ok: baseline_git_ok, baseline_git_hash_ok: baseline_git_hash_ok, paths: applied_paths, before: before_pretty, after: after_pretty, id: id}

    if dry_run do
      if show_diff do
        {before_path, after_path, out} = write_temp_and_prepare_diff(info)
        {:ok, Map.merge(info, %{diff_before: before_path, diff_after: after_path, diff: out})}
      else
        {:ok, info}
      end
    else
      File.write!(target_path, after_pretty)
      if show_diff do
        {before_path, after_path, out} = write_temp_and_prepare_diff(info)
        {:ok, Map.merge(info, %{diff_before: before_path, diff_after: after_path, diff: out})}
      else
        {:ok, info}
      end
    end
  end

  defp apply_op!(doc, base, %{"op" => op, "path" => path} = o) do
    ptr = normalize_ptr(base, path)
    case op do
      "add" -> json_put(doc, ptr, Map.fetch!(o, "value"), :add)
      "replace" -> json_put(doc, ptr, Map.fetch!(o, "value"), :replace)
      "remove" -> json_remove(doc, ptr)
      other -> Mix.raise("Unsupported op: #{inspect(other)}")
    end
  end

  defp normalize_ptr("", p), do: p
    
  defp normalize_ptr(nil, p), do: p
  defp normalize_ptr(base, p) do
    base = if base == "/", do: "", else: base
    p = if String.starts_with?(p, "/"), do: p, else: "/" <> p
    base <> p
  end

  # JSON Pointer utilities (very small subset)
  defp json_put(doc, path, value, mode) when is_binary(path) do
    tokens = pointer_tokens(path)
    put_in_pointer(doc, tokens, value, mode)
  end

  defp json_remove(doc, path) do
    tokens = pointer_tokens(path)
    remove_in_pointer(doc, tokens)
  end

  defp pointer_tokens(""), do: []
  defp pointer_tokens("/"), do: []
  defp pointer_tokens(path) do
    path
    |> String.trim_leading("/")
    |> String.split("/", trim: true)
    |> Enum.map(&String.replace(&1, ["~1", "~0"], fn "~1" -> "/"; "~0" -> "~" end))
    |> Enum.map(&decode_index/1)
  end

  defp decode_index(seg) do
    case Integer.parse(seg) do
      {i, ""} -> {:idx, i}
      _ -> {:key, seg}
    end
  end

  defp put_in_pointer(doc, [], _val, _mode), do: doc
  defp put_in_pointer(doc, [{:key, k}], val, :replace) when is_map(doc), do: Map.put(doc, k, val)
  defp put_in_pointer(doc, [{:key, k}], val, :add) when is_map(doc), do: Map.put(doc, k, val)
  defp put_in_pointer(list, [{:idx, i}], val, mode) when is_list(list) do
    cond do
      mode == :replace and i < length(list) -> List.replace_at(list, i, val)
      mode == :add and i == length(list) -> list ++ [val]
      mode == :add and i < length(list) -> List.insert_at(list, i, val)
      true -> Mix.raise("Invalid list index #{i} for mode #{mode}")
    end
  end
  defp put_in_pointer(doc, [{:key, k} | rest], val, mode) when is_map(doc) do
    child = Map.get(doc, k, default_for(rest))
    Map.put(doc, k, put_in_pointer(child, rest, val, mode))
  end
  defp put_in_pointer(list, [{:idx, i} | rest], val, mode) when is_list(list) do
    ensure = if i < length(list), do: Enum.at(list, i), else: default_for(rest)
    updated = put_in_pointer(ensure, rest, val, mode)
    cond do
      i < length(list) -> List.replace_at(list, i, updated)
      i == length(list) -> list ++ [updated]
      true -> Mix.raise("Invalid list index #{i}")
    end
  end
  defp put_in_pointer(_other, _rest, _val, _mode), do: Mix.raise("Unsupported structure for pointer")

  defp remove_in_pointer(doc, [{:key, k}]) when is_map(doc), do: Map.delete(doc, k)
  defp remove_in_pointer(list, [{:idx, i}]) when is_list(list) and i < length(list), do: List.delete_at(list, i)
  defp remove_in_pointer(doc, [{:key, k} | rest]) when is_map(doc) do
    case Map.fetch(doc, k) do
      {:ok, v} -> Map.put(doc, k, remove_in_pointer(v, rest))
      :error -> doc
    end
  end
  defp remove_in_pointer(list, [{:idx, i} | rest]) when is_list(list) and i < length(list) do
    v = Enum.at(list, i)
    List.replace_at(list, i, remove_in_pointer(v, rest))
  end
  defp remove_in_pointer(other, _), do: other

  defp default_for([{:idx, _} | _]), do: []
  defp default_for([{:key, _} | _]), do: %{}

  defp req!(opts, key), do: Keyword.get(opts, key) || Mix.raise("Missing --#{key}")

  defp compare_hash(alg, content, expected_hex) do
    try do
      actual = :crypto.hash(alg, content) |> Base.encode16(case: :lower)
      String.downcase(expected_hex) == actual
    rescue
      _ -> false
    end
  end

  defp git_show_file(dir, rev, rel_path) do
    if File.dir?(Path.join(dir, ".git")) do
      {out, status} = System.cmd("git", ["-C", dir, "show", rev <> ":" <> rel_path], stderr_to_stdout: true)
      if status == 0, do: {:ok, out}, else: {:error, {:git_error, out}}
    else
      {:error, :not_git_repo}
    end
  end

  defp pointer_exists?(doc, path) when is_binary(path) do
    tokens = pointer_tokens(path)
    case get_in_pointer(doc, tokens) do
      {:ok, _v} -> true
      :error -> false
    end
  end

  defp get_in_pointer(doc, []), do: {:ok, doc}
  defp get_in_pointer(doc, [{:key, k} | rest]) when is_map(doc) do
    case Map.fetch(doc, k) do
      {:ok, v} -> get_in_pointer(v, rest)
      :error -> :error
    end
  end
  defp get_in_pointer(list, [{:idx, i} | rest]) when is_list(list) do
    if i < length(list) do
      v = Enum.at(list, i)
      get_in_pointer(v, rest)
    else
      :error
    end
  end
  defp get_in_pointer(_other, _rest), do: :error

  defp type_tag(v) when is_map(v), do: :object
  defp type_tag(v) when is_list(v), do: :array
  defp type_tag(v) when is_binary(v), do: :string
  defp type_tag(v) when is_number(v), do: :number
  defp type_tag(v) when is_boolean(v), do: :boolean
  defp type_tag(nil), do: :null
  defp type_tag(_), do: :other

  defp write_temp_and_prepare_diff(info) do
    before = info[:before]
    after_content = info[:after]
    id = info[:id]
    file = info[:file]
    base_dir = Path.join([File.cwd!(), "work", ".tmp", id])
    File.mkdir_p!(base_dir)
    before_path = Path.join(base_dir, Path.basename(file) <> ".before.json")
    after_path = Path.join(base_dir, Path.basename(file) <> ".after.json")
    File.write!(before_path, before)
    File.write!(after_path, after_content)
    {out, _} = System.cmd("git", ["--no-pager", "diff", "--no-index", "--no-color", before_path, after_path], stderr_to_stdout: true)
    {before_path, after_path, out}
  end

  defp print_diff_preview(%{file: file} = info) do
    case write_temp_and_prepare_diff(info) do
      {before_path, after_path, out} ->
        Mix.shell().info("\n--- Unified diff (#{file})\n#{before_path} -> #{after_path}\n\n" <> out)
      _ -> :ok
    end
  end
end
