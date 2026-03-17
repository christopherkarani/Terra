fn main() {
    println!("cargo:rustc-link-search=native=../zig-core/zig-out/lib");
    println!("cargo:rustc-link-lib=static=terra");
    println!("cargo:rerun-if-changed=../zig-core/include/terra.h");
}
