use std::env;
use std::path::{Path, PathBuf};
use std::process::Command;

fn main() {
    println!("cargo:rerun-if-env-changed=TERRA_LIB_DIR");
    println!("cargo:rerun-if-env-changed=TERRA_ZIG_TARGET");
    println!("cargo:rerun-if-env-changed=TARGET");
    println!("cargo:rerun-if-changed=../zig-core/include/terra.h");
    println!("cargo:rerun-if-changed=../zig-core/src");
    println!("cargo:rerun-if-changed=../zig-core/build.zig");

    let lib_dir = match env::var_os("TERRA_LIB_DIR") {
        Some(path) => PathBuf::from(path),
        None => build_zig_core(),
    };

    println!("cargo:rustc-link-search=native={}", lib_dir.display());
    println!("cargo:rustc-link-lib=static=terra");
}

fn build_zig_core() -> PathBuf {
    let zig_target = env::var("TERRA_ZIG_TARGET").unwrap_or_else(|_| cargo_target_to_zig());
    let manifest_dir = PathBuf::from(env::var_os("CARGO_MANIFEST_DIR").expect("CARGO_MANIFEST_DIR is set"));
    let zig_core = manifest_dir
        .parent()
        .expect("terra-rust has a repository parent")
        .join("zig-core");

    let status = Command::new("zig")
        .arg("build")
        .arg(format!("-Dtarget={zig_target}"))
        .arg("-Doptimize=Debug")
        .current_dir(&zig_core)
        .status()
        .unwrap_or_else(|error| {
            panic!(
                "failed to run `zig build` in {}: {error}. Install Zig or set TERRA_LIB_DIR to a directory containing libterra.a",
                display_path(&zig_core)
            )
        });

    if !status.success() {
        panic!(
            "`zig build -Dtarget={zig_target} -Doptimize=Debug` failed in {}",
            display_path(&zig_core)
        );
    }

    zig_core.join("zig-out").join("lib")
}

fn cargo_target_to_zig() -> String {
    match env::var("TARGET").as_deref() {
        Ok("aarch64-apple-darwin") => "aarch64-macos".to_string(),
        Ok("x86_64-apple-darwin") => "x86_64-macos".to_string(),
        Ok("aarch64-unknown-linux-gnu") => "aarch64-linux-gnu".to_string(),
        Ok("x86_64-unknown-linux-gnu") => "x86_64-linux-gnu".to_string(),
        Ok("aarch64-unknown-linux-musl") => "aarch64-linux-musl".to_string(),
        Ok("x86_64-unknown-linux-musl") => "x86_64-linux-musl".to_string(),
        Ok(target) => panic!(
            "unsupported Cargo target `{target}` for automatic Zig build; set TERRA_ZIG_TARGET or TERRA_LIB_DIR"
        ),
        Err(error) => panic!("TARGET is not set: {error}"),
    }
}

fn display_path(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}
