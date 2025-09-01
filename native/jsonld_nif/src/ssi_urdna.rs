#[cfg(feature = "ssi_urdna2015")]
pub mod ssi_urdna {
    // NOTE: Compiles only when the `ssi_urdna2015` feature is enabled.
    // Version pinned to ssi 0.11.0. Wire here to ssi's URDNA2015 implementation.
    // Interface: take N-Quads input (UTF-8), return canonical N-Quads string.
    //
    // TODO(impl): After confirming ssi 0.11.0 APIs, parse N-Quads to a dataset,
    // call URDNA2015 canonicalization, and serialize canonical N-Quads.
    // Likely modules: `ssi::rdf` (dataset/types), `ssi::urdna2015` or `ssi::rdf::canon`.

    pub fn canonicalize_nquads(nquads: &str) -> Result<String, String> {
        // TODO: Replace with ssi 0.11.0 URDNA2015 canonicalization.
        // Interim: provide deterministic lexicographic N-Quads ordering.
        let mut lines: Vec<&str> = nquads
            .split('\n')
            .map(|l| l.trim_end())
            .filter(|l| !l.is_empty() && !l.starts_with('#'))
            .collect();
        lines.sort_unstable();
        let out = if lines.is_empty() { String::new() } else { lines.join("\n") + "\n" };
        Ok(out)
    }
}

#[cfg(not(feature = "ssi_urdna2015"))]
pub mod ssi_urdna {
    pub fn canonicalize_nquads(_nquads: &str) -> Result<String, String> {
        Err("ssi_urdna2015 feature not enabled".to_string())
    }
}
