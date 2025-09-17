defmodule JsonldEx.Native do
  @version Mix.Project.config()[:version]
  @nif_features (
    case System.get_env("JSONLD_NIF_FEATURES") do
      nil -> []
      "" -> []
      "none" -> []
      f -> String.split(f, ",", trim: true)
    end
  )

  # Prefer precompiled NIFs from GitHub releases; fall back to local build if
  # download is unavailable or JSONLD_NIF_FORCE_BUILD is set.
  # Skip NIF integration when building documentation (MIX_ENV=docs) to avoid
  # attempting downloads/compilation during hexdocs publishing.
  if Code.ensure_loaded?(Mix) and function_exported?(Mix, :env, 0) and Mix.env() == :docs do
    @doc false
    def __skip_nif_loading_for_docs__, do: :ok
  else
    use RustlerPrecompiled,
      otp_app: :jsonld_ex,
      crate: "jsonld_nif",
      version: @version,
      base_url: "https://github.com/zpc-sh/jsonld_ex/releases/download/v#{@version}",
      force_build: System.get_env("JSONLD_NIF_FORCE_BUILD") in ["1", "true"],
      features: @nif_features,
      # Temporarily reduced target set to match current release matrix.
      # Unsupported hosts fall back to local build automatically.
      targets: [
        "x86_64-unknown-linux-gnu",
        "aarch64-unknown-linux-gnu",
        "aarch64-apple-darwin"
      ],
      nif_versions: [
        "2.16",
        "2.15",
        "2.14"
      ]
  end

  def expand(_input, _opts), do: :erlang.nif_error(:nif_not_loaded)
  def expand_binary(_input, _opts), do: :erlang.nif_error(:nif_not_loaded)
  def compact(_input, _context, _opts), do: :erlang.nif_error(:nif_not_loaded) 
  def flatten(_input, _context, _opts), do: :erlang.nif_error(:nif_not_loaded)
  def to_rdf(_input, _opts), do: :erlang.nif_error(:nif_not_loaded)
  def from_rdf(_input, _opts), do: :erlang.nif_error(:nif_not_loaded)
  def frame(_input, _frame, _opts), do: :erlang.nif_error(:nif_not_loaded)
  def parse_semantic_version(_version), do: :erlang.nif_error(:nif_not_loaded)
  def compare_versions(_version1, _version2), do: :erlang.nif_error(:nif_not_loaded)
  def satisfies_requirement(_version, _requirement), do: :erlang.nif_error(:nif_not_loaded)
  def query_nodes(_document, _pattern), do: :erlang.nif_error(:nif_not_loaded)
  def cache_context(_context, _key), do: :erlang.nif_error(:nif_not_loaded)
  def batch_process(_operations), do: :erlang.nif_error(:nif_not_loaded)
  def batch_expand(_documents), do: :erlang.nif_error(:nif_not_loaded)
  def validate_document(_document, _opts), do: :erlang.nif_error(:nif_not_loaded)
  def optimize_for_storage(_document), do: :erlang.nif_error(:nif_not_loaded)
  def detect_cycles(_graph), do: :erlang.nif_error(:nif_not_loaded)
  def generate_blueprint_context(_blueprint_data, _opts), do: :erlang.nif_error(:nif_not_loaded)
  def merge_documents(_documents, _opts), do: :erlang.nif_error(:nif_not_loaded)
  def build_dependency_graph(_blueprints), do: :erlang.nif_error(:nif_not_loaded)
  
  # High-performance diff operations
  def diff_structural(_old_document, _new_document, _opts), do: :erlang.nif_error(:nif_not_loaded)
  def diff_operational(_old_document, _new_document, _opts), do: :erlang.nif_error(:nif_not_loaded)
  def diff_semantic(_old_document, _new_document, _opts), do: :erlang.nif_error(:nif_not_loaded)
  def patch_structural(_document, _patch, _opts), do: :erlang.nif_error(:nif_not_loaded)
  def patch_operational(_document, _patch, _opts), do: :erlang.nif_error(:nif_not_loaded)
  def patch_semantic(_document, _patch, _opts), do: :erlang.nif_error(:nif_not_loaded)
  def merge_diffs_operational(_diffs, _opts), do: :erlang.nif_error(:nif_not_loaded)
  def normalize_rdf_graph(_document, _algorithm), do: :erlang.nif_error(:nif_not_loaded)
  def compute_lcs_array(_old_array, _new_array), do: :erlang.nif_error(:nif_not_loaded)
  def text_diff_myers(_old_text, _new_text), do: :erlang.nif_error(:nif_not_loaded)
end
