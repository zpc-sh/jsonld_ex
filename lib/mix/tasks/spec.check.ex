defmodule Mix.Tasks.Spec.Check do
  use Mix.Task
  @shortdoc "Run common validations: lint + thread render"
  @moduledoc """
  Usage:
    mix spec.check --id <request_id>

  Runs `spec.lint` (which also renders the thread) and reports consolidated status.
  """

  @impl true
  def run(argv) do
    {opts, _, _} = OptionParser.parse(argv, switches: [id: :string])
    id = Keyword.get(opts, :id) || Mix.raise("Missing --id")

    try do
      Mix.Task.run("spec.lint", ["--id", id])
      Mix.shell().info("Check OK for #{id}")
    rescue
      e -> Mix.raise("Check failed for #{id}: #{inspect(e)}")
    end
  end
end

