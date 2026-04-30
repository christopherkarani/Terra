# Terra Rust Bindings

Rust bindings for Terra's native GenAI observability core.

## Build

The crate links against `libterra.a`. By default, `build.rs` looks for the library built from the repository Zig core:

```bash
cd ../zig-core
zig build

cd ../terra-rust
cargo test
```

If the library lives somewhere else, set `TERRA_LIB_DIR` to the directory containing `libterra.a` before running Cargo.

## Package Verification

Release validation must verify the packaged crate copy, not just the repository
checkout. Build the native library once, then pass its absolute directory to
Cargo:

```bash
cd ../zig-core
zig build

cd ../terra-rust
TERRA_LIB_DIR="$(pwd)/../zig-core/zig-out/lib" cargo package --allow-dirty
```

`cargo package` builds from Cargo's temporary packaged crate copy. That copy does
not contain sibling `../zig-core`, so `TERRA_LIB_DIR` is required unless the crate
is built from a full Terra repository checkout.
