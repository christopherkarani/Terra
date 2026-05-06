use std::env;
use std::path::{Path, PathBuf};
use std::process::Command;

fn main() {
    println!("cargo:rerun-if-env-changed=TERRA_LIB_DIR");
    println!("cargo:rerun-if-env-changed=TERRA_ZIG_TARGET");
    println!("cargo:rerun-if-env-changed=TARGET");

    let manifest_dir =
        PathBuf::from(env::var_os("CARGO_MANIFEST_DIR").expect("CARGO_MANIFEST_DIR is set"));
    let repo_zig_core = manifest_dir
        .parent()
        .map(|parent| parent.join("zig-core"))
        .filter(|path| path.join("build.zig").is_file());

    if repo_zig_core.is_some() {
        println!("cargo:rerun-if-changed=../zig-core/include/terra.h");
        println!("cargo:rerun-if-changed=../zig-core/src");
        println!("cargo:rerun-if-changed=../zig-core/build.zig");
    }

    let lib_dir = match env::var_os("TERRA_LIB_DIR") {
        Some(path) => validate_lib_dir(PathBuf::from(path), "TERRA_LIB_DIR"),
        None => match repo_zig_core {
            Some(zig_core) => build_zig_core(&zig_core),
            None => panic!(
                "terra-rust was packaged without sibling ../zig-core. Set TERRA_LIB_DIR to an \
absolute directory containing libterra.a when building or verifying the packaged crate, for \
example `TERRA_LIB_DIR=/path/to/zig-core/zig-out/lib cargo package`. Automatic Zig builds are \
only supported from a full Terra repository checkout."
            ),
        },
    };

    println!("cargo:rustc-link-search=native={}", lib_dir.display());
    println!("cargo:rustc-link-lib=static=terra");
}

fn build_zig_core(zig_core: &Path) -> PathBuf {
    let zig_target = env::var("TERRA_ZIG_TARGET").unwrap_or_else(|_| cargo_target_to_zig());

    let status = Command::new("zig")
        .arg("build")
        .arg(format!("-Dtarget={zig_target}"))
        .arg("-Doptimize=Debug")
        .current_dir(zig_core)
        .status()
        .unwrap_or_else(|error| {
            panic!(
                "failed to run `zig build` in {}: {error}. Install Zig or set TERRA_LIB_DIR to a directory containing libterra.a",
                display_path(zig_core)
            )
        });

    if !status.success() {
        panic!(
            "`zig build -Dtarget={zig_target} -Doptimize=Debug` failed in {}",
            display_path(zig_core)
        );
    }

    validate_lib_dir(zig_core.join("zig-out").join("lib"), "zig build output")
}

fn validate_lib_dir(lib_dir: PathBuf, source: &str) -> PathBuf {
    let library = lib_dir.join("libterra.a");
    if !library.is_file() {
        panic!(
            "{source} must contain libterra.a; expected {}",
            display_path(&library)
        );
    }
    lib_dir
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
