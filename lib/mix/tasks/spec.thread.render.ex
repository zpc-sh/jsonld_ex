defmodule Mix.Tasks.Spec.Thread.Render do
  use Mix.Task
  @shortdoc "Render a single Markdown thread file from request + messages"
  @moduledoc """
  Usage:
    mix spec.thread.render --id <request_id>

  Renders `work/spec_requests/<id>/thread.md` combining request.json and all inbox/outbox messages
  in chronological order, as a single Markdown file suitable for review by both sides.
  """

  @impl true
  def run(argv) do
    {opts, _, _} = OptionParser.parse(argv, switches: [id: :string])
    id = Keyword.get(opts, :id) || Mix.raise("Missing --id")

    root = Path.join(["work", "spec_requests", id])
    req_path = Path.join(root, "request.json")
    request = File.exists?(req_path) && Jason.decode!(File.read!(req_path)) || %{}

    msgs =
      [Path.join(root, "inbox"), Path.join(root, "outbox")]
      |> Enum.flat_map(fn dir -> Path.wildcard(Path.join(dir, "msg_*.json")) end)
      |> Enum.map(fn path -> {path, Jason.decode!(File.read!(path))} end)
      |> Enum.map(fn {path, m} ->
        ts = canonical_ts(m["created_at"]) || mtime_dt!(path)
        {path, m, ts}
      end)
      |> Enum.sort_by(fn {_p, _m, ts} -> ts end, {:asc, DateTime})

    out = ["# Spec Thread: #{id}\n\n"]
    out = out ++ ["## Request\n\n", "```json\n", Jason.encode!(request, pretty: true), "\n```\n\n"]

    out =
      Enum.reduce(msgs, out, fn {_path, m, ts}, acc ->
        header = "### [#{m["type"]}] #{m["from"]["project"]}/#{m["from"]["agent"]} @ #{iso8601(ts)}\n\n"
        ref =
          case m["ref"] do
            nil -> ""
            %{"path" => p} = r -> "Ref: #{p} #{r["json_pointer"] || ""}\n\n"
            _ -> ""
          end
        body = m["body"] || ""
        files = m["attachments"] || []
        files_block = if files == [], do: "", else: "Attachments:\n\n" <> Enum.map_join(files, "\n", &("- " <> &1)) <> "\n\n"
        acc ++ [header, ref, body, "\n\n", files_block]
      end)

    thread_path = Path.join(root, "thread.md")
    File.write!(thread_path, IO.iodata_to_binary(out))
    Mix.shell().info("Rendered #{thread_path}")
  end

  defp canonical_ts(nil), do: nil
  defp canonical_ts(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _offset} -> DateTime.truncate(dt, :second)
      _ -> nil
    end
  end

  defp iso8601(%DateTime{} = dt), do: DateTime.to_iso8601(dt)

  defp mtime_dt!(path) do
    {:ok, stat} = File.stat(path)
    stat.mtime |> NaiveDateTime.to_erl() |> NaiveDateTime.from_erl!() |> DateTime.from_naive!("Etc/UTC") |> DateTime.truncate(:second)
  end
end
