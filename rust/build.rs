use std::env;
use std::path::PathBuf;

fn main() {
    println!("cargo:rerun-if-env-changed=FFMPEG_DIR");

    let target_os = env::var("CARGO_CFG_TARGET_OS").unwrap_or_default();
    if target_os != "macos" && target_os != "ios" {
        return;
    }

    let Some(ffmpeg_dir) = env::var_os("FFMPEG_DIR") else {
        return;
    };

    let mut lib_dir = PathBuf::from(ffmpeg_dir);
    lib_dir.push("lib");

    let lame_archive = lib_dir.join("libmp3lame.a");
    if lame_archive.exists() {
        println!("cargo:rustc-link-search=native={}", lib_dir.display());
        println!("cargo:rustc-link-lib=static=mp3lame");
    }
}
