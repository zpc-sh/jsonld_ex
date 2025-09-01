defmodule Mix.Tasks.Spec.Export.Jsonld do
  use Mix.Task
  @shortdoc "Export request, ack, and messages as JSON-LD into the hub"
  @moduledoc """
  Usage:
    mix spec.export.jsonld --id <req> --project <name> --hub ../lang-spec-hub

  Writes JSON-LD files under <hub>/requests/<project>/<id>/jsonld/ using the hub context path:
    ../../../schemas/contexts/spec.jsonld
  """

  @impl true
  def run(argv) do
    {opts, _, _} = OptionParser.parse(argv, switches: [id: :string, project: :string, hub: :string])
    id = req!(opts, :id)
    project = req!(opts, :project)
    hub = req!(opts, :hub)

    src_root = Path.join([File.cwd!(), "work", "spec_requests", id])
    File.dir?(src_root) || Mix.raise("Request not found: #{src_root}")
    dest_root = Path.join([hub, "requests", project, id, "jsonld"]) 
    File.mkdir_p!(dest_root)

    context_rel = Path.join(["..", "..", "..", "schemas", "contexts", "spec.jsonld"]) # ../../../schemas/contexts/spec.jsonld

    # request
    req_json = read_json!(Path.join(src_root, "request.json"))
    statuses = status_list(src_root)
    req_ld = %{
      "@context" => context_rel,
      "@id" => "urn:spec:" <> project <> ":" <> id,
      "@type" => "SpecRequest",
      "project" => project,
      "title" => req_json["title"],
      "motivation" => req_json["motivation"],
      "api" => req_json["api"],
      "errors" => req_json["errors"],
      "determinism" => req_json["determinism"],
      "telemetry" => req_json["telemetry"],
      "tests" => req_json["tests"],
      "acceptance" => req_json["acceptance"],
      "attachments" => req_json["attachments"],
      "statuses" => statuses,
      "status" => List.last(statuses || ["proposed"]),
      "updatedAt" => DateTime.utc_now() |> DateTime.to_iso8601()
    }
    File.write!(Path.join(dest_root, "request.jsonld"), Jason.encode_to_iodata!(req_ld, pretty: true))

    # ack (optional)
    ack_path = Path.join(src_root, "ack.json")
    if File.exists?(ack_path) do
      ack_json = read_json!(ack_path)
      ack_ld = %{
        "@context" => context_rel,
        "@id" => "urn:specack:" <> project <> ":" <> id,
        "@type" => "SpecAck",
        "owner" => ack_json["owner"],
        "contact" => ack_json["contact"],
        "status" => ack_json["status"],
        "eta" => ack_json["eta_iso8601"],
        "updatedAt" => ack_json["updated_at"]
      }
      File.write!(Path.join(dest_root, "ack.jsonld"), Jason.encode_to_iodata!(ack_ld, pretty: true))
    end

    # messages (inbox + outbox)
    for dir <- ["inbox", "outbox"] do
      Path.wildcard(Path.join(src_root, dir <> "/msg_*.json"))
      |> Enum.each(fn msg_path ->
        m = read_json!(msg_path)
        basename = Path.basename(msg_path) |> String.replace(~r/\.json$/, "")
        msg_ld = %{
          "@context" => context_rel,
          "@id" => "urn:specmsg:" <> project <> ":" <> id <> ":" <> basename,
          "@type" => "SpecMessage",
          "from" => m["from"],
          "type" => m["type"],
          "ref" => m["ref"],
          "body" => m["body"],
          "attachments" => m["attachments"],
          "relatesTo" => "urn:spec:" <> project <> ":" <> id,
          "status" => m["status"],
          "createdAt" => m["created_at"],
          "updatedAt" => m["updated_at"]
        }
        out_dir = Path.join(dest_root, "messages")
        File.mkdir_p!(out_dir)
        File.write!(Path.join(out_dir, basename <> ".jsonld"), Jason.encode_to_iodata!(msg_ld, pretty: true))
      end)
    end

    Mix.shell().info("Exported JSON-LD to #{dest_root}")
  end

  defp read_json!(path), do: Jason.decode!(File.read!(path))
  defp status_list(root) do
    Path.wildcard(Path.join(root, "*.status"))
    |> Enum.map(&Path.basename/1)
    |> Enum.map(&String.trim_trailing(&1, ".status"))
    |> Enum.sort()
  end

  defp req!(opts, key), do: Keyword.get(opts, key) || Mix.raise("Missing --#{key}")
end
