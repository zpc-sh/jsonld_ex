Mix.start()
Mix.shell(Mix.Shell.Process)

doc = %{
  "@context" => "https://schema.org/",
  "@type" => "Person",
  "name" => "Jane Doe",
  "age" => 30
}

json = Jason.encode!(doc)

IO.puts("Expand → compact → to_rdf demo\n")

{:ok, expanded} = JsonldEx.Native.expand(json, [])
IO.puts("expanded bytes: #{IO.iodata_length(expanded)}")

context = %{"name" => "https://schema.org/name"}
ctx_json = Jason.encode!(context)
{:ok, compacted} = JsonldEx.Native.compact(expanded, ctx_json, [])
IO.puts("compacted bytes: #{IO.iodata_length(compacted)}")

{:ok, rdf} = JsonldEx.Native.to_rdf(json, [])
IO.puts("rdf bytes: #{IO.iodata_length(rdf)}")

IO.puts("\nOK")

