use flutter_rust_bridge_codegen::codegen;
use flutter_rust_bridge_codegen::config::RawOpts;

fn main() {
    // Generate Dart/Rust glue code
    // This normally runs via 'flutter_rust_bridge_codegen' CLI
    // But setting up build.rs to do it is cleaner if tools are present.
    // If not, we skip.
    println!("cargo:rerun-if-changed=src/api.rs");
}
