//! Content-addressed image assets under `{data_root}/assets/`.
//!
//! Agents send base64 once; the document stores a short `asset:{sha}.{ext}` ref.
//! Inline `data:` URLs are accepted on write and externalized here.

use std::collections::HashSet;
use std::fs;
use std::path::{Path, PathBuf};

use std::io::Read;

use base64::{engine::general_purpose::STANDARD as B64, Engine as _};
use flate2::read::ZlibDecoder;
use sha2::{Digest, Sha256};

use crate::error::{Error, Result};
use crate::id::CanvasId;
use crate::schema::{CanvasDocument, Cover, Section};

/// Max encoded image bytes accepted for a cover or inline image.
pub const MAX_IMAGE_BYTES: usize = 2 * 1024 * 1024;
/// Max width × height (decompression-bomb guard; checked from headers only).
pub const MAX_IMAGE_PIXELS: u64 = 4_000_000;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ImageFormat {
    Png,
    Jpeg,
}

impl ImageFormat {
    pub fn ext(self) -> &'static str {
        match self {
            Self::Png => "png",
            Self::Jpeg => "jpg",
        }
    }
}

#[derive(Debug, Clone)]
pub struct ImageMeta {
    pub format: ImageFormat,
    pub width: u32,
    pub height: u32,
    pub byte_len: usize,
}

/// Directory for content-addressed assets.
pub fn assets_dir(root: &Path) -> PathBuf {
    root.join("assets")
}

/// Sniff PNG/JPEG from magic bytes (ignore declared mime).
pub fn sniff_format(bytes: &[u8]) -> Result<ImageFormat> {
    if bytes.len() >= 8 && bytes.starts_with(&[0x89, b'P', b'N', b'G', b'\r', b'\n', 0x1a, b'\n']) {
        return Ok(ImageFormat::Png);
    }
    if bytes.len() >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF {
        return Ok(ImageFormat::Jpeg);
    }
    Err(Error::Validation(
        "image: unsupported format (PNG or JPEG only)".into(),
    ))
}

/// Parse dimensions from PNG IHDR or JPEG SOF without a full decode.
pub fn read_dimensions(bytes: &[u8], format: ImageFormat) -> Result<(u32, u32)> {
    match format {
        ImageFormat::Png => read_png_dimensions(bytes),
        ImageFormat::Jpeg => read_jpeg_dimensions(bytes),
    }
}

fn read_png_dimensions(bytes: &[u8]) -> Result<(u32, u32)> {
    let (width, height, _) = parse_png_ihdr(bytes)?;
    Ok((width, height))
}

struct PngIhdr {
    width: u32,
    height: u32,
    bit_depth: u8,
    color_type: u8,
    interlace: u8,
}

fn parse_png_ihdr(bytes: &[u8]) -> Result<(u32, u32, PngIhdr)> {
    // Signature (8) + length (4) + "IHDR" (4) + data (13) + crc (4)
    if bytes.len() < 33 {
        return Err(Error::Validation("image: truncated PNG".into()));
    }
    if &bytes[12..16] != b"IHDR" {
        return Err(Error::Validation("image: PNG missing IHDR".into()));
    }
    let width = u32::from_be_bytes([bytes[16], bytes[17], bytes[18], bytes[19]]);
    let height = u32::from_be_bytes([bytes[20], bytes[21], bytes[22], bytes[23]]);
    if width == 0 || height == 0 {
        return Err(Error::Validation("image: PNG has zero dimensions".into()));
    }
    let ihdr = PngIhdr {
        width,
        height,
        bit_depth: bytes[24],
        color_type: bytes[25],
        interlace: bytes[28],
    };
    Ok((width, height, ihdr))
}

/// Inflate PNG IDAT and verify uncompressed size matches IHDR (rejects truncated/corrupt streams).
fn verify_png_idat(bytes: &[u8]) -> Result<()> {
    let (_, _, ihdr) = parse_png_ihdr(bytes)?;
    let mut i = 8usize;
    let mut idat = Vec::new();
    while i + 8 <= bytes.len() {
        let len = u32::from_be_bytes([bytes[i], bytes[i + 1], bytes[i + 2], bytes[i + 3]]) as usize;
        let ctype = &bytes[i + 4..i + 8];
        let data_start = i + 8;
        let data_end = data_start
            .checked_add(len)
            .ok_or_else(|| Error::Validation("image: truncated PNG chunk".into()))?;
        if data_end + 4 > bytes.len() {
            return Err(Error::Validation("image: truncated PNG chunk".into()));
        }
        if ctype == b"IDAT" {
            idat.extend_from_slice(&bytes[data_start..data_end]);
        }
        i = data_end + 4; // skip CRC
        if ctype == b"IEND" {
            break;
        }
    }
    if idat.is_empty() {
        return Err(Error::Validation("image: PNG missing IDAT".into()));
    }
    let mut decoder = ZlibDecoder::new(&idat[..]);
    let mut raw = Vec::new();
    decoder.read_to_end(&mut raw).map_err(|e| {
        Error::Validation(format!(
            "image: corrupt PNG pixel data (IDAT inflate failed: {e})"
        ))
    })?;

    // Samples per pixel for standard color types (bit depth 8/16).
    let samples = match ihdr.color_type {
        0 => 1u32, // gray
        2 => 3,    // RGB
        3 => 1,    // indexed
        4 => 2,    // gray+alpha
        6 => 4,    // RGBA
        other => {
            return Err(Error::Validation(format!(
                "image: unsupported PNG color type {other}"
            )));
        }
    };
    if !matches!(ihdr.bit_depth, 1 | 2 | 4 | 8 | 16) {
        return Err(Error::Validation(format!(
            "image: unsupported PNG bit depth {}",
            ihdr.bit_depth
        )));
    }
    if ihdr.interlace != 0 {
        // Adam7 size math is messy; inflate success is enough to reject truncations.
        if raw.is_empty() {
            return Err(Error::Validation(
                "image: PNG interlaced IDAT decompressed empty".into(),
            ));
        }
        return Ok(());
    }
    let bpp = ((u32::from(ihdr.bit_depth) * samples + 7) / 8) as usize;
    let row = 1 + (ihdr.width as usize).saturating_mul(bpp);
    let expected = (ihdr.height as usize).saturating_mul(row);
    if raw.len() != expected {
        return Err(Error::Validation(format!(
            "image: corrupt PNG pixel data (expected {expected} uncompressed bytes, got {})",
            raw.len()
        )));
    }
    Ok(())
}

fn read_jpeg_dimensions(bytes: &[u8]) -> Result<(u32, u32)> {
    let mut i = 2usize; // skip SOI
    while i + 9 < bytes.len() {
        if bytes[i] != 0xFF {
            return Err(Error::Validation("image: invalid JPEG markers".into()));
        }
        while i < bytes.len() && bytes[i] == 0xFF {
            i += 1;
        }
        if i >= bytes.len() {
            break;
        }
        let marker = bytes[i];
        i += 1;
        // Standalone markers without length
        if marker == 0xD9 || marker == 0xDA {
            break;
        }
        if i + 1 >= bytes.len() {
            break;
        }
        let len = u16::from_be_bytes([bytes[i], bytes[i + 1]]) as usize;
        if len < 2 || i + len > bytes.len() {
            return Err(Error::Validation("image: truncated JPEG segment".into()));
        }
        // SOF0..SOF3, SOF5..SOF7, SOF9..SOF11, SOF13..SOF15
        let is_sof = matches!(
            marker,
            0xC0 | 0xC1 | 0xC2 | 0xC3 | 0xC5 | 0xC6 | 0xC7 | 0xC9 | 0xCA | 0xCB | 0xCD | 0xCE
                | 0xCF
        );
        if is_sof {
            if len < 7 {
                return Err(Error::Validation("image: truncated JPEG SOF".into()));
            }
            let height = u16::from_be_bytes([bytes[i + 3], bytes[i + 4]]) as u32;
            let width = u16::from_be_bytes([bytes[i + 5], bytes[i + 6]]) as u32;
            if width == 0 || height == 0 {
                return Err(Error::Validation(
                    "image: JPEG has zero dimensions".into(),
                ));
            }
            return Ok((width, height));
        }
        i += len;
    }
    Err(Error::Validation("image: JPEG missing SOF".into()))
}

/// Validate bytes against caps; return metadata.
pub fn validate_image_bytes(bytes: &[u8]) -> Result<ImageMeta> {
    if bytes.is_empty() {
        return Err(Error::Validation("image: empty payload".into()));
    }
    if bytes.len() > MAX_IMAGE_BYTES {
        return Err(Error::Validation(format!(
            "image: {} bytes exceeds max {} bytes",
            bytes.len(),
            MAX_IMAGE_BYTES
        )));
    }
    let format = sniff_format(bytes)?;
    let (width, height) = read_dimensions(bytes, format)?;
    let pixels = (width as u64).saturating_mul(height as u64);
    if pixels > MAX_IMAGE_PIXELS {
        return Err(Error::Validation(format!(
            "image: {width}×{height} ({pixels} px) exceeds max {MAX_IMAGE_PIXELS} pixels"
        )));
    }
    // IHDR/SOF alone are not enough — agents sometimes emit truncated base64 that still
    // has a plausible header. Inflate PNG IDAT (JPEG keeps SOF-only checks for now).
    if format == ImageFormat::Png {
        verify_png_idat(bytes)?;
    }
    Ok(ImageMeta {
        format,
        width,
        height,
        byte_len: bytes.len(),
    })
}

/// Decode a data URL or raw base64 into bytes.
pub fn decode_image_input(input: &str) -> Result<Vec<u8>> {
    let trimmed = input.trim();
    let b64 = if let Some(rest) = trimmed.strip_prefix("data:") {
        let comma = rest
            .find(',')
            .ok_or_else(|| Error::Validation("image: malformed data URL".into()))?;
        let header = &rest[..comma];
        if !header.contains(";base64") {
            return Err(Error::Validation(
                "image: data URL must be base64-encoded".into(),
            ));
        }
        &rest[comma + 1..]
    } else {
        trimmed
    };
    B64.decode(b64.trim())
        .map_err(|e| Error::Validation(format!("image: invalid base64 ({e})")))
}

/// Validate an image source string (without resolving files).
///
/// Accepted: `asset:{64hex}.{png|jpg}`, `data:image/...;base64,...`
/// Rejected: remote http(s), bare paths, empty.
pub fn validate_image_source(source: &str, ctx: &str) -> Result<()> {
    let s = source.trim();
    if s.is_empty() {
        return Err(Error::Validation(format!("{ctx}: source is required")));
    }
    if s.starts_with("http://") || s.starts_with("https://") {
        return Err(Error::Validation(format!(
            "{ctx}: remote URLs are not supported (use set_canvas_cover or data:/asset:)"
        )));
    }
    if let Some(rest) = s.strip_prefix("asset:") {
        validate_asset_ref(rest, ctx)?;
        return Ok(());
    }
    if s.starts_with("data:") {
        // Cheap structural check; full decode happens on externalize.
        if !s.contains(";base64,") {
            return Err(Error::Validation(format!(
                "{ctx}: data URL must be data:image/...;base64,..."
            )));
        }
        return Ok(());
    }
    if s.starts_with("file://") {
        return Err(Error::Validation(format!(
            "{ctx}: file:// is not supported; use asset: refs from set_canvas_cover / update_canvas"
        )));
    }
    Err(Error::Validation(format!(
        "{ctx}: source must be asset:… or data:image/…;base64,…"
    )))
}

fn validate_asset_ref(rest: &str, ctx: &str) -> Result<()> {
    let (hash, ext) = rest
        .rsplit_once('.')
        .ok_or_else(|| Error::Validation(format!("{ctx}: asset ref must be asset:{{sha}}.{{ext}}")))?;
    if hash.len() != 64 || !hash.chars().all(|c| c.is_ascii_hexdigit()) {
        return Err(Error::Validation(format!(
            "{ctx}: asset hash must be 64 hex chars"
        )));
    }
    match ext {
        "png" | "jpg" => Ok(()),
        other => Err(Error::Validation(format!(
            "{ctx}: unsupported asset extension `{other}` (png|jpg)"
        ))),
    }
}

/// Resolve `asset:{sha}.{ext}` to an absolute path under `assets/`, with containment.
pub fn resolve_asset(root: &Path, source: &str) -> Result<PathBuf> {
    let s = source.trim();
    let rest = s.strip_prefix("asset:").ok_or_else(|| {
        Error::Validation("resolve: expected asset: reference".into())
    })?;
    validate_asset_ref(rest, "resolve")?;
    let dir = assets_dir(root);
    let path = dir.join(rest);
    let canon_dir = fs::canonicalize(&dir).unwrap_or(dir.clone());
    // Parent must exist for canonicalize of the file; check prefix after join.
    if let Ok(canon) = fs::canonicalize(&path) {
        if !canon.starts_with(&canon_dir) {
            return Err(Error::Validation(
                "resolve: asset path escapes assets directory".into(),
            ));
        }
        return Ok(canon);
    }
    // File may not exist yet — still reject path tricks structurally.
    if path
        .components()
        .any(|c| matches!(c, std::path::Component::ParentDir))
    {
        return Err(Error::Validation(
            "resolve: asset path must not contain ..".into(),
        ));
    }
    if path.parent().map(|p| p != dir.as_path()).unwrap_or(true) {
        return Err(Error::Validation(
            "resolve: asset must be a single filename under assets/".into(),
        ));
    }
    Ok(path)
}

/// Write validated image bytes; return `asset:{sha}.{ext}` (skip write if already present).
pub fn write_asset(root: &Path, bytes: &[u8]) -> Result<(String, ImageMeta)> {
    let meta = validate_image_bytes(bytes)?;
    let mut hasher = Sha256::new();
    hasher.update(bytes);
    let hash = hex_encode(&hasher.finalize());
    let filename = format!("{hash}.{}", meta.format.ext());
    let dir = assets_dir(root);
    fs::create_dir_all(&dir)?;
    let path = dir.join(&filename);
    if !path.exists() {
        let tmp = path.with_extension(format!("{}.tmp", meta.format.ext()));
        fs::write(&tmp, bytes)?;
        fs::rename(&tmp, &path)?;
    }
    Ok((format!("asset:{filename}"), meta))
}

fn hex_encode(bytes: impl AsRef<[u8]>) -> String {
    bytes
        .as_ref()
        .iter()
        .map(|b| format!("{b:02x}"))
        .collect()
}

/// Collect all `asset:` refs from a document.
pub fn collect_asset_refs(doc: &CanvasDocument) -> HashSet<String> {
    let mut out = HashSet::new();
    if let Some(Cover { source, .. }) = &doc.cover {
        if source.starts_with("asset:") {
            out.insert(source.clone());
        }
    }
    collect_section_assets(&doc.sections, &mut out);
    if let Some(detail) = &doc.detail {
        collect_section_assets(&detail.sections, &mut out);
    }
    out
}

fn collect_section_assets(sections: &[Section], out: &mut HashSet<String>) {
    for s in sections {
        match s {
            Section::Image { source, .. } => {
                if source.starts_with("asset:") {
                    out.insert(source.clone());
                }
            }
            Section::Group { children, .. } => collect_section_assets(children, out),
            _ => {}
        }
    }
}

/// Externalize any `data:` sources in cover / image sections to `asset:` refs.
pub fn externalize_document(root: &Path, mut doc: CanvasDocument) -> Result<CanvasDocument> {
    if let Some(cover) = doc.cover.take() {
        let source = externalize_source(root, &cover.source)?;
        doc.cover = Some(Cover {
            source,
            alt: cover.alt,
            fit: cover.fit,
        });
    }
    doc.sections = externalize_sections(root, doc.sections)?;
    if let Some(mut detail) = doc.detail.take() {
        detail.sections = externalize_sections(root, detail.sections)?;
        doc.detail = Some(detail);
    }
    Ok(doc)
}

fn externalize_sections(root: &Path, sections: Vec<Section>) -> Result<Vec<Section>> {
    sections
        .into_iter()
        .map(|s| externalize_section(root, s))
        .collect()
}

fn externalize_section(root: &Path, section: Section) -> Result<Section> {
    match section {
        Section::Image {
            source,
            caption,
            height,
            priority,
        } => {
            let source = externalize_source(root, &source)?;
            Ok(Section::Image {
                source,
                caption,
                height,
                priority,
            })
        }
        Section::Group {
            direction,
            gap,
            align,
            children,
            weight,
            priority,
        } => {
            let children = externalize_sections(root, children)?;
            Ok(Section::Group {
                direction,
                gap,
                align,
                children,
                weight,
                priority,
            })
        }
        other => Ok(other),
    }
}

fn externalize_source(root: &Path, source: &str) -> Result<String> {
    let s = source.trim();
    if s.starts_with("asset:") {
        validate_image_source(s, "image")?;
        // Ensure the file exists under assets/.
        let path = resolve_asset(root, s)?;
        if !path.exists() {
            return Err(Error::Validation(format!(
                "image: asset not found: {s}"
            )));
        }
        return Ok(s.to_string());
    }
    if s.starts_with("data:") {
        let bytes = decode_image_input(s)?;
        let (r, _) = write_asset(root, &bytes)?;
        return Ok(r);
    }
    validate_image_source(s, "image")?;
    Ok(s.to_string())
}

/// Delete unreferenced assets (not cited by any current canvas or history snapshot).
pub fn gc(root: &Path) -> Result<usize> {
    let dir = assets_dir(root);
    if !dir.exists() {
        return Ok(0);
    }
    let mut live = HashSet::new();
    for id in CanvasId::ALL {
        let path = root.join("canvases").join(id.file_name());
        if let Ok(raw) = fs::read_to_string(&path) {
            if let Ok(doc) = serde_json::from_str::<CanvasDocument>(&raw) {
                live.extend(collect_asset_refs(&doc));
            }
        }
        let hist = root.join("history").join(id.as_str());
        if let Ok(rd) = fs::read_dir(&hist) {
            for ent in rd.flatten() {
                let p = ent.path();
                if p.extension().and_then(|e| e.to_str()) != Some("json") {
                    continue;
                }
                if p.file_name().and_then(|n| n.to_str()) == Some("index.json") {
                    continue;
                }
                if let Ok(raw) = fs::read_to_string(&p) {
                    if let Ok(doc) = serde_json::from_str::<CanvasDocument>(&raw) {
                        live.extend(collect_asset_refs(&doc));
                    }
                }
            }
        }
    }
    let mut removed = 0usize;
    for ent in fs::read_dir(&dir)?.flatten() {
        let path = ent.path();
        let Some(name) = path.file_name().and_then(|n| n.to_str()) else {
            continue;
        };
        let key = format!("asset:{name}");
        if !live.contains(&key) {
            if fs::remove_file(&path).is_ok() {
                removed += 1;
            }
        }
    }
    Ok(removed)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tiny_png() -> Vec<u8> {
        // Minimal valid 1×1 RGB PNG (zlib-compressed IDAT).
        vec![
            0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48,
            0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x02, 0x00, 0x00,
            0x00, 0x90, 0x77, 0x53, 0xDE, 0x00, 0x00, 0x00, 0x0C, 0x49, 0x44, 0x41, 0x54, 0x78,
            0xDA, 0x63, 0xF8, 0xCF, 0xC0, 0x00, 0x00, 0x03, 0x01, 0x01, 0x00, 0xF7, 0x03, 0x41,
            0x43, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
        ]
    }

    fn tmp() -> PathBuf {
        let dir = std::env::temp_dir().join(format!(
            "ac-assets-{}",
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn sniff_and_dims_png() {
        let png = tiny_png();
        let meta = validate_image_bytes(&png).unwrap();
        assert_eq!(meta.format, ImageFormat::Png);
        assert_eq!((meta.width, meta.height), (1, 1));
    }

    #[test]
    fn rejects_corrupt_png_idat() {
        // Valid chunk framing + CRC, invalid zlib stream inside IDAT.
        let mut bad = tiny_png();
        let idat = bad.windows(4).position(|w| w == b"IDAT").expect("IDAT");
        let data_start = idat + 4;
        let data_end = data_start + 12; // tiny_png IDAT length is 12
        for b in &mut bad[data_start..data_end] {
            *b = 0xFF;
        }
        let crc = png_crc(&bad[idat..data_end]);
        bad[data_end..data_end + 4].copy_from_slice(&crc.to_be_bytes());
        let err = validate_image_bytes(&bad).unwrap_err().to_string();
        assert!(
            err.contains("corrupt PNG") || err.contains("IDAT"),
            "{err}"
        );
    }

    fn png_crc(type_and_data: &[u8]) -> u32 {
        const POLY: u32 = 0xEDB8_8320;
        let mut crc = 0xFFFF_FFFFu32;
        for &b in type_and_data {
            crc ^= u32::from(b);
            for _ in 0..8 {
                if crc & 1 != 0 {
                    crc = (crc >> 1) ^ POLY;
                } else {
                    crc >>= 1;
                }
            }
        }
        !crc
    }

    #[test]
    fn rejects_oversize_bytes() {
        let mut big = tiny_png();
        big.resize(MAX_IMAGE_BYTES + 1, 0);
        let err = validate_image_bytes(&big).unwrap_err().to_string();
        assert!(err.contains("exceeds max"), "{err}");
    }

    #[test]
    fn write_dedupes() {
        let root = tmp();
        let png = tiny_png();
        let (a, _) = write_asset(&root, &png).unwrap();
        let (b, _) = write_asset(&root, &png).unwrap();
        assert_eq!(a, b);
        assert!(a.starts_with("asset:"));
        assert!(resolve_asset(&root, &a).unwrap().exists());
    }

    #[test]
    fn reject_traversal() {
        let root = tmp();
        fs::create_dir_all(assets_dir(&root)).unwrap();
        let err = resolve_asset(&root, "asset:../evil.png").unwrap_err().to_string();
        assert!(err.contains("hash") || err.contains("..") || err.contains("escapes"), "{err}");
    }

    #[test]
    fn data_url_externalize() {
        let root = tmp();
        let b64 = B64.encode(tiny_png());
        let data = format!("data:image/png;base64,{b64}");
        let mut doc = CanvasDocument::empty();
        doc.cover = Some(Cover {
            source: data,
            alt: "x".into(),
            fit: None,
        });
        let out = externalize_document(&root, doc).unwrap();
        let src = &out.cover.as_ref().unwrap().source;
        assert!(src.starts_with("asset:"), "{src}");
        assert!(resolve_asset(&root, src).unwrap().exists());
    }
}
