fn main() {
    println!("cargo:rustc-link-search=native=../zig-core/zig-out/lib");
    println!("cargo:rustc-link-lib=static=terra");
    println!("cargo:rerun-if-changed=../zig-core/include/terra.h");
    println!("cargo:rerun-if-changed=../zig-core/src");
    println!("cargo:rerun-if-changed=../zig-core/build.zig");
    println!("cargo:rerun-if-changed=../zig-core/zig-out/lib/libterra.a");
}
