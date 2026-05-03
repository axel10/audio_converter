#[cfg(any(target_os = "android", target_os = "ios", target_os = "macos"))]
pub mod apple;
#[cfg(any(target_os = "android", target_os = "ios", target_os = "macos"))]
pub mod common;
#[cfg(any(target_os = "android", target_os = "ios", target_os = "macos"))]
pub mod debug;
#[cfg(any(target_os = "android", target_os = "ios", target_os = "macos"))]
pub mod formats;
pub mod models;
#[cfg(any(target_os = "android", target_os = "ios", target_os = "macos"))]
pub mod simple;
#[cfg(any(target_os = "android", target_os = "ios", target_os = "macos"))]
pub mod transcoder;

#[cfg(not(any(target_os = "android", target_os = "ios", target_os = "macos")))]
pub mod simple;
