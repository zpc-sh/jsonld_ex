# .formatter.exs - JsonldEx Elixir Code Formatter Configuration
#
# This file configures the Elixir code formatter for the JsonldEx project.
# It includes all relevant modules, dependencies, and formatting rules for
# consistent code style across the entire codebase.
#
# Key Features:
# - Optimized line length (100 characters) for readability
# - Import dependencies for proper formatting of external library calls
# - Comprehensive locals_without_parens for JsonldEx API functions
# - Export configuration for use in subdirectories
# - Support for Mix tasks, tests, and core library modules
#
# Usage:
#   mix format              # Format all files
#   mix format --check-formatted  # Check if files need formatting
#   make format             # Format both Elixir and Rust code
#   make lint               # Format check + additional linting

[
  # File patterns to format
  inputs: [
    "{mix,.formatter}.exs",
    "{config,lib,test}/**/*.{ex,exs}"
  ],

  # Line length (default is 98, we'll use a slightly more conservative 100)
  line_length: 100,

  # Import dependencies for proper formatting
  # These ensure that functions from external libraries are formatted correctly
  import_deps: [
    # JSON encoding/decoding
    :jason,
    # Precompiled NIF support
    :rustler_precompiled,
    # NIF development support
    :rustler
  ],

  # Plugins for additional formatting support
  # Currently none, but can be extended for specialized formatting
  plugins: [],

  # Local dependencies - modules from this project
  # These functions are formatted without parentheses when called with a single argument
  # This improves readability for DSL-like function calls and API usage
  locals_without_parens: [
    # JsonldEx API functions
    expand: 1,
    expand: 2,
    expand_turbo: 1,
    expand_turbo: 2,
    compact: 2,
    compact: 3,
    flatten: 2,
    flatten: 3,
    frame: 2,
    frame: 3,
    to_rdf: 1,
    to_rdf: 2,
    from_rdf: 1,
    from_rdf: 2,

    # Canonicalization and hashing
    c14n: 1,
    c14n: 2,
    hash: 1,
    hash: 2,
    equal?: 2,
    equal?: 3,

    # Diff operations
    diff_structural: 2,
    diff_structural: 3,
    diff_operational: 2,
    diff_operational: 3,
    diff_semantic: 2,
    diff_semantic: 3,
    patch_structural: 2,
    patch_structural: 3,
    patch_operational: 2,
    patch_operational: 3,
    patch_semantic: 2,
    patch_semantic: 3,

    # Native NIF functions
    parse_semantic_version: 1,
    compare_versions: 2,
    satisfies_requirement: 2,
    query_nodes: 2,
    cache_context: 2,
    batch_process: 1,
    batch_expand: 1,
    validate_document: 2,
    optimize_for_storage: 1,
    detect_cycles: 1,
    generate_blueprint_context: 2,
    merge_documents: 2,
    build_dependency_graph: 1,
    normalize_rdf_graph: 2,
    compute_lcs_array: 2,
    text_diff_myers: 2,

    # Mix task helpers
    read_json!: 1,
    write_json!: 2,
    ensure_dir!: 1,
    file_exists?: 1,
    git_rev: 1,
    apply_patch: 2,
    validate_patch: 1,
    compute_hash: 1,
    format_output: 2,

    # Test helpers and assertions
    assert_expanded: 2,
    assert_compacted: 2,
    assert_flattened: 2,
    assert_rdf_equal: 2,
    assert_diff_equal: 2,
    refute_diff_equal: 2,

    # Configuration and options
    with_context: 2,
    with_options: 2,
    with_features: 2
  ],

  # Export locals_without_parens for use in subdirectories
  # This allows subdirectories to inherit the main formatting rules
  # Essential for consistent formatting across the entire project
  export: [
    locals_without_parens: [
      # Core JsonldEx functions
      expand: 1,
      expand: 2,
      compact: 2,
      compact: 3,
      flatten: 2,
      flatten: 3,
      frame: 2,
      frame: 3,
      to_rdf: 1,
      to_rdf: 2,
      from_rdf: 1,
      from_rdf: 2,
      c14n: 1,
      c14n: 2,
      hash: 1,
      hash: 2,
      equal?: 2,
      equal?: 3
    ]
  ],

  # Subdirectories with their own formatting rules
  # These directories can have specialized formatting while inheriting the base config
  subdirectories: [
    # Test files may have different formatting needs
    "test",
    # Mix tasks often have specific formatting requirements
    "lib/mix/tasks"
  ]
]
