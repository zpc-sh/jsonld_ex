defmodule Mix.Tasks.Spec.Lint do
  use Mix.Task
  @shortdoc "Validate request, ack, and messages; check attachments; render thread"
  @moduledoc """
  Usage:
    mix spec.lint --id <request_id>

  Performs lightweight checks:
  - request.json exists and is valid JSON
  - ack.json (if present) is valid JSON
  - messages in inbox/outbox are valid JSON and have bodies
  - attachments referenced by messages exist
  - renders thread.md successfully
  """

  @impl true
  def run(argv) do
    {opts, _, _} = OptionParser.parse(argv, switches: [id: :string])
    id = Keyword.get(opts, :id) || Mix.raise("Missing --id")

    root = Path.join(["work", "spec_requests", id])
    schema_root = Path.join(["work", "spec_requests"]) 
    req_path = Path.join(root, "request.json")
    ack_path = Path.join(root, "ack.json")

    ok =
      file_json(req_path, "request.json") and
      ack_ok?(ack_path, schema_root) and
      messages_ok?(root, schema_root) and
      render_ok?(id)

    if ok, do: Mix.shell().info("Lint OK for #{id}"), else: Mix.raise("Lint failed for #{id}")
  end

  defp file_json(path, label) do
    with true <- File.exists?(path) || (Mix.shell().error("Missing #{label}"); false),
         {:ok, _} <- decode(path) do
      true
    else
      _ -> false
    end
  end

  defp optional_json(path, _label) do
    if File.exists?(path) do
      case decode(path) do
        {:ok, _} -> true
        _ -> (Mix.shell().error("Invalid JSON: #{path}"); false)
      end
    else
      true
    end
  end

  defp ack_ok?(ack_path, schema_root) do
    if File.exists?(ack_path) do
      with {:ok, ack} <- decode(ack_path),
           {:ok, schema} <- read_schema(Path.join(schema_root, "ack.schema.json")),
           :ok <- validate(ack, schema) do
        true
      else
        {:error, reason} -> Mix.shell().error("Ack validation failed: #{inspect(reason)}"); false
        _ -> Mix.shell().error("Invalid ack JSON: #{ack_path}"); false
      end
    else
      true
    end
  end

  defp decode(path) do
    try do
      {:ok, Jason.decode!(File.read!(path))}
    rescue
      _ -> {:error, :invalid}
    end
  end

  defp messages_ok?(root, schema_root) do
    schema = read_schema(Path.join(schema_root, "message.schema.json")) |> case do
      {:ok, s} -> {:ok, s}
      other -> other
    end
    [Path.join(root, "inbox"), Path.join(root, "outbox")]
    |> Enum.flat_map(&Path.wildcard(Path.join(&1, "msg_*.json")))
    |> Enum.map(fn mpath ->
      case decode(mpath) do
        {:ok, m} ->
          base_checks =
            with true <- is_binary(m["body"]) and byte_size(m["body"]) > 0 or (Mix.shell().error("Empty body: #{mpath}"); false),
                 true <- attachments_ok?(root, mpath, m["attachments"] || []) do
              true
            else
              _ -> false
            end

          schema_checks = case schema do
            {:ok, s} -> case validate(m, s) do
              :ok -> true
              {:error, reason} -> Mix.shell().error("Message schema fail (#{mpath}): #{inspect(reason)}"); false
            end
            _ -> true
          end
          base_checks and schema_checks
        _ -> Mix.shell().error("Invalid message JSON: #{mpath}"); false
      end
    end)
    |> Enum.all?()
  end

  defp attachments_ok?(root, mpath, files) do
    Enum.map(files, fn rel ->
      cond do
        is_binary(rel) and not String.contains?(rel, "..") and File.exists?(Path.join(root, rel)) -> true
        is_binary(rel) and String.contains?(rel, "..") -> Mix.shell().error("Unsafe attachment path (..): #{rel} in #{mpath}"); false
        true -> Mix.shell().error("Missing attachment for #{mpath}: #{inspect(rel)}"); false
      end
    end) |> Enum.all?()
  end

  defp read_schema(path) do
    try do
      {:ok, Jason.decode!(File.read!(path))}
    rescue
      _ -> {:error, :schema_load_failed}
    end
  end

  # Minimal JSON Schema validator supporting: required, type, enum, and nested object required
  defp validate(doc, %{"type" => "object"} = schema) when is_map(doc) do
    with :ok <- validate_required(doc, schema["required"] || []),
         :ok <- validate_properties(doc, schema["properties"] || %{}) do
      :ok
    end
  end
  defp validate(doc, %{"type" => "array", "items" => item_schema}) when is_list(doc) do
    Enum.reduce_while(doc, :ok, fn v, :ok -> case validate(v, item_schema) do :ok -> {:cont, :ok}; err -> {:halt, err} end end)
  end
  defp validate(value, %{"type" => "string", "enum" => enum}) when is_binary(value) do
    if value in enum, do: :ok, else: {:error, {:enum, value, enum}}
  end
  defp validate(value, %{"type" => "string"}) when is_binary(value), do: :ok
  defp validate(value, %{"type" => "object"}) when is_map(value), do: :ok
  defp validate(value, %{"type" => "array"}) when is_list(value), do: :ok
  defp validate(_value, %{}), do: :ok

  defp validate_required(doc, required) do
    missing = Enum.filter(required, fn k -> not Map.has_key?(doc, k) end)
    if missing == [], do: :ok, else: {:error, {:missing, missing}}
  end

  defp validate_properties(doc, props) do
    Enum.reduce_while(props, :ok, fn {k, pschema}, :ok ->
      case Map.fetch(doc, k) do
        :error -> {:cont, :ok}
        {:ok, v} ->
          # Recurse for nested objects with required
          case pschema do
            %{"type" => "object"} = s ->
              case validate(v, s) do :ok -> {:cont, :ok}; err -> {:halt, {:error, {k, err}}} end
            %{"enum" => _} = s -> case validate(v, Map.put(s, "type", s["type"] || infer_type(v))) do :ok -> {:cont, :ok}; err -> {:halt, {:error, {k, err}}} end
            %{"type" => _} = s -> case validate(v, s) do :ok -> {:cont, :ok}; err -> {:halt, {:error, {k, err}}} end
            _ -> {:cont, :ok}
          end
      end
    end)
  end

  defp infer_type(v) when is_binary(v), do: "string"
  defp infer_type(v) when is_map(v), do: "object"
  defp infer_type(v) when is_list(v), do: "array"
  defp infer_type(_), do: "string"

  defp render_ok?(id) do
    try do
      Mix.Task.run("spec.thread.render", ["--id", id])
      true
    rescue
      e -> Mix.shell().error("thread render failed: #{inspect(e)}"); false
    end
  end
end
