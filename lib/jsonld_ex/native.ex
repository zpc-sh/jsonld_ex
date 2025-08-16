defmodule JsonldEx.Native do
  use Rustler, otp_app: :jsonld_ex, crate: "jsonld_nif"

  def expand(_input, _opts), do: :erlang.nif_error(:nif_not_loaded)
  def compact(_input, _context, _opts), do: :erlang.nif_error(:nif_not_loaded) 
  def flatten(_input, _context, _opts), do: :erlang.nif_error(:nif_not_loaded)
  def to_rdf(_input, _opts), do: :erlang.nif_error(:nif_not_loaded)
  def from_rdf(_input, _opts), do: :erlang.nif_error(:nif_not_loaded)
  def frame(_input, _frame, _opts), do: :erlang.nif_error(:nif_not_loaded)
  def parse_semantic_version(_version), do: :erlang.nif_error(:nif_not_loaded)
  def compare_versions(_version1, _version2), do: :erlang.nif_error(:nif_not_loaded)
  def satisfies_requirement?(_version, _requirement), do: :erlang.nif_error(:nif_not_loaded)
  def query_nodes(_document, _pattern), do: :erlang.nif_error(:nif_not_loaded)
  def cache_context(_context, _key), do: :erlang.nif_error(:nif_not_loaded)
  def batch_process(_operations), do: :erlang.nif_error(:nif_not_loaded)
  def validate_document(_document, _opts), do: :erlang.nif_error(:nif_not_loaded)
  def optimize_for_storage(_document), do: :erlang.nif_error(:nif_not_loaded)
end
