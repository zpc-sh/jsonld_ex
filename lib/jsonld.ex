defmodule JSONLD do
  @moduledoc """
  Public API façade matching the spec workflow examples.

  Delegates to JsonldEx.C14n for canonicalization and hashing.
  """

  alias JsonldEx.C14n

  @doc """
  Canonicalize a JSON(-LD) term.
  Returns {:ok, %{nquads: iodata, bnode_map: map}} | {:error, term}
  """
  def c14n(term, opts \\ []), do: C14n.c14n(term, opts)

  @doc """
  Hash a JSON(-LD) term. Returns {:ok, %{algorithm: atom, form: atom, hash: binary, quad_count: non_neg_integer}}
  """
  def hash(term, opts \\ []), do: C14n.hash(term, opts)

  @doc """
  Compare two JSON(-LD) terms for canonical equality. Returns boolean.
  """
  def equal?(a, b, opts \\ []), do: C14n.equal?(a, b, opts)
end

