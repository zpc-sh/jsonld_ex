defmodule Mix.Tasks.Spec.Hash do
  use Mix.Task
  @shortdoc "Compute and store canonical hashes for a spec request"
  @moduledoc """
  Usage:
    mix spec.hash --id <request_id>

  Writes work/spec_requests/<id>/hashes.json containing stable_json and, if
  available, urdna2015_nquads hashes for request.json.
  """

  @impl true
  def run(argv) do
    {opts, _, _} = OptionParser.parse(argv, switches: [id: :string])
    id = Keyword.get(opts, :id) || Mix.raise("Missing --id")

    root = Path.join([File.cwd!(), "work", "spec_requests", id])
    req_path = Path.join(root, "request.json")
    File.exists?(req_path) || Mix.raise("Missing request.json: #{req_path}")

    request = Jason.decode!(File.read!(req_path))

    {:ok, stable} = JSONLD.hash(request, form: :stable_json)
    urdna = case JSONLD.hash(request, form: :urdna2015_nquads) do
      {:ok, u} -> u
      _ -> nil
    end

    out = %{
      "stable_json" => stable,
      "urdna2015_nquads" => urdna
    }
    out_path = Path.join(root, "hashes.json")
    File.write!(out_path, Jason.encode_to_iodata!(out, pretty: true))
    Mix.shell().info("Wrote #{out_path}")
  end
end

