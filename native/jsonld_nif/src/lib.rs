use rustler::{Encoder, Env, NifResult, Term};
use serde_json::{json, Value};
use semver::{Version, VersionReq};

use std::sync::Arc;
use lazy_static::lazy_static;
use lru::LruCache;
use std::sync::Mutex;
use std::num::NonZeroUsize;

mod atoms {
    rustler::atoms! {
        ok,
        error,
        lt,
        eq,
        gt,
        nil,
        true_atom = "true",
        false_atom = "false",
    }
}

lazy_static! {
    static ref CONTEXT_CACHE: Arc<Mutex<LruCache<String, Arc<String>>>> =
        Arc::new(Mutex::new(LruCache::new(NonZeroUsize::new(100).unwrap())));
}

// JSON-LD Core Operations

#[rustler::nif]
fn expand<'a>(env: Env<'a>, input: String, _opts: Vec<(String, String)>) -> NifResult<Term<'a>> {
    match serde_json::from_str::<Value>(&input) {
        Ok(json_val) => {
            let expanded = simple_expand(json_val);
            let result = serde_json::to_string(&expanded).unwrap_or_else(|_| "{}".to_string());
            Ok((atoms::ok(), result).encode(env))
        }
        Err(e) => Ok((atoms::error(), e.to_string()).encode(env))
    }
}

#[rustler::nif]
fn compact<'a>(env: Env<'a>, input: String, context: String, _opts: Vec<(String, String)>) -> NifResult<Term<'a>> {
    match (serde_json::from_str::<Value>(&input), serde_json::from_str::<Value>(&context)) {
        (Ok(json_val), Ok(ctx_val)) => {
            let compacted = simple_compact(json_val, ctx_val);
            let result = serde_json::to_string(&compacted).unwrap_or_else(|_| "{}".to_string());

            Ok((atoms::ok(), result).encode(env))
        }
        (Err(e), _) | (_, Err(e)) => Ok((atoms::error(), e.to_string()).encode(env))
    }
}

#[rustler::nif]
fn flatten<'a>(env: Env<'a>, input: String, context: Option<String>, _opts: Vec<(String, String)>) -> NifResult<Term<'a>> {
    match serde_json::from_str::<Value>(&input) {
        Ok(json_val) => {
            let ctx_val = context.and_then(|c| serde_json::from_str::<Value>(&c).ok());
            let flattened = simple_flatten(json_val, ctx_val);
            let result = serde_json::to_string(&flattened).unwrap_or_else(|_| "{}".to_string());
            Ok((atoms::ok(), result).encode(env))
        }
        Err(e) => Ok((atoms::error(), e.to_string()).encode(env))
    }
}

#[rustler::nif]
fn to_rdf<'a>(env: Env<'a>, input: String, _opts: Vec<(String, String)>) -> NifResult<Term<'a>> {
    match serde_json::from_str::<Value>(&input) {
        Ok(json_val) => {
            let rdf = convert_to_rdf_simple(json_val);
            Ok((atoms::ok(), rdf).encode(env))
        }
        Err(e) => Ok((atoms::error(), e.to_string()).encode(env))
    }
}

#[rustler::nif]
fn from_rdf<'a>(env: Env<'a>, _input: String, _opts: Vec<(String, String)>) -> NifResult<Term<'a>> {
    // Simplified RDF to JSON-LD conversion
    let result = json!({
        "@context": {},
        "@graph": []
    });
    Ok((atoms::ok(), result.to_string()).encode(env))
}

// Semantic Versioning Operations

#[rustler::nif]
fn parse_semantic_version<'a>(env: Env<'a>, version_str: String) -> NifResult<Term<'a>> {
    match Version::parse(&version_str) {
        Ok(v) => {
            let result = json!({
                "@context": {
                    "@vocab": "https://semver.org/spec/v2.0.0/"
                },
                "@type": "Version",
                "major": v.major,
                "minor": v.minor,
                "patch": v.patch,
                "prerelease": if v.pre.is_empty() { Value::Null } else { Value::String(v.pre.to_string()) },
                "build": if v.build.is_empty() { Value::Null } else { Value::String(v.build.to_string()) },
                "full_version": v.to_string()
            });
            Ok((atoms::ok(), result.to_string()).encode(env))
        }
        Err(e) => Ok((atoms::error(), e.to_string()).encode(env))
    }
}

#[rustler::nif]
fn compare_versions<'a>(env: Env<'a>, version1: String, version2: String) -> NifResult<Term<'a>> {
    match (Version::parse(&version1), Version::parse(&version2)) {
        (Ok(v1), Ok(v2)) => {
            let result = match v1.cmp(&v2) {
                std::cmp::Ordering::Less => atoms::lt(),
                std::cmp::Ordering::Equal => atoms::eq(),
                std::cmp::Ordering::Greater => atoms::gt(),
            };
            Ok(result.encode(env))
        }
        (Err(e), _) | (_, Err(e)) => Ok((atoms::error(), e.to_string()).encode(env))
    }
}

#[rustler::nif]
fn satisfies_requirement<'a>(env: Env<'a>, version: String, requirement: String) -> NifResult<Term<'a>> {
    // Handle npm-style requirements
    let req_str = convert_npm_requirement(&requirement);
    
    match (Version::parse(&version), VersionReq::parse(&req_str)) {
        (Ok(v), Ok(req)) => Ok(req.matches(&v).encode(env)),
        (Err(e), _) | (_, Err(e)) => Ok((atoms::error(), e.to_string()).encode(env))
    }
}

// Blueprint-specific Operations

#[rustler::nif]
fn generate_blueprint_context<'a>(env: Env<'a>, _blueprint_data: String, _opts: Vec<(String, String)>) -> NifResult<Term<'a>> {
    let context = json!({
        "@context": {
            "@vocab": "https://blueprints.ash-hq.org/vocab/",
            "ash": "https://ash-hq.org/ontology/",
            "name": "ash:name",
            "type": "ash:type",
            "attributes": {
                "@id": "ash:attributes",
                "@container": "@set"
            },
            "relationships": {
                "@id": "ash:relationships",
                "@container": "@set"
            }
        }
    });
    Ok((atoms::ok(), context.to_string()).encode(env))
}

#[rustler::nif]
fn merge_documents<'a>(env: Env<'a>, documents: Vec<String>, _opts: Vec<(String, String)>) -> NifResult<Term<'a>> {
    let mut merged = json!({});
    
    for doc_str in documents {
        if let Ok(doc) = serde_json::from_str::<Value>(&doc_str) {
            merge_json(&mut merged, &doc);
        }
    }
    
    Ok((atoms::ok(), merged.to_string()).encode(env))
}

#[rustler::nif]
fn validate_document<'a>(env: Env<'a>, document: String, _opts: Vec<(String, String)>) -> NifResult<Term<'a>> {
    match serde_json::from_str::<Value>(&document) {
        Ok(doc) => {
            let mut errors = Vec::new();
            
            if let Value::Object(ref obj) = doc {
                if !obj.contains_key("@context") {
                    errors.push("Missing @context");
                }
                if !obj.contains_key("@type") && !obj.contains_key("@id") {
                    errors.push("Missing @type or @id");
                }
            } else {
                errors.push("Document must be an object");
            }
            
            if errors.is_empty() {
                Ok(atoms::ok().encode(env))
            } else {
                Ok((atoms::error(), errors).encode(env))
            }
        }
        Err(e) => Ok((atoms::error(), e.to_string()).encode(env))
    }
}

#[rustler::nif]
fn optimize_for_storage<'a>(env: Env<'a>, document: String) -> NifResult<Term<'a>> {
    match serde_json::from_str::<Value>(&document) {
        Ok(mut doc) => {
            optimize_json(&mut doc);
            Ok((atoms::ok(), doc.to_string()).encode(env))
        }
        Err(e) => Ok((atoms::error(), e.to_string()).encode(env))
    }
}

// Graph Operations

#[rustler::nif]
fn frame<'a>(env: Env<'a>, input: String, frame_str: String, _opts: Vec<(String, String)>) -> NifResult<Term<'a>> {
    match (serde_json::from_str::<Value>(&input), serde_json::from_str::<Value>(&frame_str)) {
        (Ok(input_val), Ok(frame_val)) => {
            let framed = simple_frame(input_val, frame_val);
            Ok((atoms::ok(), framed.to_string()).encode(env))
        }
        (Err(e), _) | (_, Err(e)) => Ok((atoms::error(), e.to_string()).encode(env))
    }
}

#[rustler::nif]
fn query_nodes<'a>(env: Env<'a>, document: String, pattern: String) -> NifResult<Term<'a>> {
    match (serde_json::from_str::<Value>(&document), serde_json::from_str::<Value>(&pattern)) {
        (Ok(doc), Ok(pat)) => {
            let matches = find_matching_nodes(&doc, &pat);
            Ok((atoms::ok(), serde_json::to_string(&matches).unwrap_or_else(|_| "[]".to_string())).encode(env))
        }
        (Err(e), _) | (_, Err(e)) => Ok((atoms::error(), e.to_string()).encode(env))
    }
}

#[rustler::nif]
fn build_dependency_graph<'a>(env: Env<'a>, blueprints: Vec<String>) -> NifResult<Term<'a>> {
    let mut nodes = Vec::new();
    let mut edges: Vec<Value> = Vec::new();
    
    for (i, bp_str) in blueprints.iter().enumerate() {
        if let Ok(bp) = serde_json::from_str::<Value>(bp_str) {
            if let Value::Object(ref obj) = bp {
                if let Some(Value::String(name)) = obj.get("name") {
                    nodes.push(json!({
                        "id": i,
                        "name": name
                    }));
                }
            }
        }
    }
    
    let graph = json!({
        "nodes": nodes,
        "edges": edges
    });
    
    Ok((atoms::ok(), graph.to_string()).encode(env))
}

#[rustler::nif]
fn detect_cycles<'a>(env: Env<'a>, _graph: String) -> NifResult<Term<'a>> {
    // Simplified cycle detection - returns empty array for now
    Ok((atoms::ok(), Vec::<Vec<String>>::new()).encode(env))
}

// Performance Utilities

#[rustler::nif]
fn cache_context<'a>(env: Env<'a>, context: String, key: String) -> NifResult<Term<'a>> {
    let mut cache = CONTEXT_CACHE.lock().unwrap();
    cache.put(key.clone(), Arc::new(context));
    Ok((atoms::ok(), key).encode(env))
}

#[rustler::nif]
fn batch_process<'a>(env: Env<'a>, operations: Vec<(String, String)>) -> NifResult<Term<'a>> {
    let mut results = Vec::new();
    
    for (op_type, args) in operations {
        let result = match op_type.as_str() {
            "expand" => {
                if let Ok(input) = serde_json::from_str::<Value>(&args) {
                    simple_expand(input).to_string()
                } else {
                    r#"{"error": "Invalid input"}"#.to_string()
                }
            }
            _ => r#"{"error": "Unknown operation"}"#.to_string()
        };
        results.push(result);
    }
    
    Ok((atoms::ok(), results).encode(env))
}

// Helper functions

fn convert_npm_requirement(req: &str) -> String {
    if req.starts_with('^') {
        req[1..].to_string()
    } else if req.starts_with('~') {
        format!("~{}", &req[1..])
    } else {
        req.to_string()
    }
}

fn simple_expand(input: Value) -> Value {
    // Simplified expansion
    if let Value::Object(obj) = input {
        let expanded;
        let mut expanded_obj = serde_json::Map::new();
        
        for (key, value) in obj {
            if key.starts_with('@') {
                expanded_obj.insert(key, value);
            } else {
                expanded_obj.insert(format!("http://example.org/{}", key), value);
            }
        }
        
        expanded = json!([expanded_obj]);
        expanded
    } else {
        input
    }
}

fn simple_compact(input: Value, context: Value) -> Value {
    let result = json!({});
    
    if let Value::Object(mut obj) = result {
        obj.insert("@context".to_string(), context);
        
        if let Value::Array(arr) = input {
            if let Some(Value::Object(first)) = arr.first() {
                for (key, value) in first {
                    let compact_key = key.split('/').last().unwrap_or(key);
                    obj.insert(compact_key.to_string(), value.clone());
                }
            }
        }
        
        Value::Object(obj)
    } else {
        input
    }
}

fn simple_flatten(input: Value, context: Option<Value>) -> Value {
    let mut nodes = Vec::new();
    extract_nodes(&input, &mut nodes);
    
    let mut result = json!({
        "@graph": nodes
    });
    
    if let Some(ctx) = context {
        if let Value::Object(ref mut obj) = result {
            obj.insert("@context".to_string(), ctx);
        }
    }
    
    result
}

fn extract_nodes(value: &Value, nodes: &mut Vec<Value>) {
    match value {
        Value::Object(obj) => {
            if obj.contains_key("@id") {
                nodes.push(value.clone());
            }
            for v in obj.values() {
                extract_nodes(v, nodes);
            }
        }
        Value::Array(arr) => {
            for v in arr {
                extract_nodes(v, nodes);
            }
        }
        _ => {}
    }
}

fn convert_to_rdf_simple(input: Value) -> String {
    let mut triples = Vec::new();
    
    if let Value::Object(obj) = input {
        let subject = obj.get("@id")
            .and_then(|v| v.as_str())
            .unwrap_or("_:blank");
        
        for (predicate, object) in &obj {
            if !predicate.starts_with('@') {
                let triple = format!("<{}> <{}> \"{}\" .", subject, predicate, object);
                triples.push(triple);
            }
        }
    }
    
    triples.join("\n")
}

fn merge_json(target: &mut Value, source: &Value) {
    if let (Value::Object(target_obj), Value::Object(source_obj)) = (target, source) {
        for (key, value) in source_obj {
            target_obj.entry(key.clone())
                .and_modify(|v| merge_json(v, value))
                .or_insert(value.clone());
        }
    }
}

fn optimize_json(value: &mut Value) {
    match value {
        Value::Object(obj) => {
            obj.retain(|_, v| !v.is_null());
            for v in obj.values_mut() {
                optimize_json(v);
            }
        }
        Value::Array(arr) => {
            for v in arr {
                optimize_json(v);
            }
        }
        _ => {}
    }
}

fn simple_frame(input: Value, frame: Value) -> Value {
    // Simplified framing
    let mut result = json!({});
    
    if let (Value::Object(input_obj), Value::Object(frame_obj)) = (input, frame) {
        for (key, _) in frame_obj {
            if let Some(value) = input_obj.get(&key) {
                if let Value::Object(ref mut result_obj) = result {
                    result_obj.insert(key, value.clone());
                }
            }
        }
    }
    
    result
}

fn find_matching_nodes(doc: &Value, pattern: &Value) -> Vec<Value> {
    let mut matches = Vec::new();
    find_nodes_recursive(doc, pattern, &mut matches);
    matches
}

fn find_nodes_recursive(value: &Value, pattern: &Value, matches: &mut Vec<Value>) {
    if matches_pattern(value, pattern) {
        matches.push(value.clone());
    }
    
    match value {
        Value::Object(obj) => {
            for v in obj.values() {
                find_nodes_recursive(v, pattern, matches);
            }
        }
        Value::Array(arr) => {
            for v in arr {
                find_nodes_recursive(v, pattern, matches);
            }
        }
        _ => {}
    }
}

fn matches_pattern(value: &Value, pattern: &Value) -> bool {
    match (value, pattern) {
        (Value::Object(v_obj), Value::Object(p_obj)) => {
            p_obj.iter().all(|(key, p_val)| {
                v_obj.get(key).map_or(false, |v_val| matches_pattern(v_val, p_val))
            })
        }
        (v, p) => v == p,
    }
}

rustler::init!(
    "Elixir.JsonldEx.Native",
    [
        expand,
        compact,
        flatten,
        to_rdf,
        from_rdf,
        parse_semantic_version,
        compare_versions,
        satisfies_requirement,
        generate_blueprint_context,
        merge_documents,
        validate_document,
        optimize_for_storage,
        frame,
        query_nodes,
        build_dependency_graph,
        detect_cycles,
        cache_context,
        batch_process
    ]
);