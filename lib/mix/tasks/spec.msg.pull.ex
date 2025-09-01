defmodule Mix.Tasks.Spec.Msg.Pull do
  use Mix.Task
  @shortdoc "Pull peer outbox messages into local inbox"
  @moduledoc """
  Usage:
    mix spec.msg.pull --id <request_id> [--from /path/to/peer/work/spec_requests/<id>/outbox]

  If --from is omitted, builds it from SPEC_HANDOFF_DIR: $SPEC_HANDOFF_DIR/<id>/outbox
  """

  @impl true
  def run(argv) do
    {opts, _, _} = OptionParser.parse(argv, switches: [id: :string, from: :string])
    id = req!(opts, :id)
    from_outbox =
      case Keyword.get(opts, :from) do
        nil ->
          base = System.get_env("SPEC_HANDOFF_DIR") || Mix.raise("Provide --from or set SPEC_HANDOFF_DIR")
          Path.join([base, id, "outbox"])
        v -> v
      end

    dest_root = Path.join(["work", "spec_requests", id])
    inbox = Path.join(dest_root, "inbox")
    File.mkdir_p!(inbox)

    for msg_path <- Path.wildcard(Path.join(from_outbox, "msg_*.json")) do
      File.cp!(msg_path, Path.join(inbox, Path.basename(msg_path)))
      Mix.shell().info("Pulled #{Path.basename(msg_path)}")
    end
  end

  defp req!(opts, key), do: Keyword.get(opts, key) || Mix.raise("Missing --#{key}")
end
