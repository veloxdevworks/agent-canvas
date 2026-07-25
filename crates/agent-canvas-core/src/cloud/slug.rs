use crate::error::{Error, Result};

/// Human-readable slug: lowercase letters, digits, hyphens; 2–64 chars.
pub fn validate_slug(slug: &str) -> Result<()> {
    let s = slug.trim();
    if s.len() < 2 || s.len() > 64 {
        return Err(Error::InvalidSlug("length must be 2–64 characters".into()));
    }
    if s.starts_with('-') || s.ends_with('-') {
        return Err(Error::InvalidSlug(
            "must not start or end with a hyphen".into(),
        ));
    }
    if !s
        .chars()
        .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '-')
    {
        return Err(Error::InvalidSlug(
            "use lowercase a-z, 0-9, and hyphens only".into(),
        ));
    }
    if s.contains("--") {
        return Err(Error::InvalidSlug("no consecutive hyphens".into()));
    }
    Ok(())
}

/// Normalize a free-form title or suggestion into a slug candidate.
pub fn normalize_slug(raw: &str) -> Result<String> {
    let mut out = String::new();
    let mut prev_hyphen = false;
    for c in raw.trim().chars() {
        let c = c.to_ascii_lowercase();
        let ok = if c.is_ascii_alphanumeric() {
            prev_hyphen = false;
            Some(c)
        } else if c == ' ' || c == '_' || c == '-' {
            if prev_hyphen || out.is_empty() {
                None
            } else {
                prev_hyphen = true;
                Some('-')
            }
        } else {
            None
        };
        if let Some(ch) = ok {
            out.push(ch);
        }
        if out.len() >= 64 {
            break;
        }
    }
    while out.ends_with('-') {
        out.pop();
    }
    validate_slug(&out)?;
    Ok(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normalizes_title() {
        assert_eq!(normalize_slug("DGII Stock").unwrap(), "dgii-stock");
        assert_eq!(normalize_slug("  Hello__World  ").unwrap(), "hello-world");
    }

    #[test]
    fn rejects_bad() {
        assert!(validate_slug("A").is_err());
        assert!(validate_slug("-ab").is_err());
        assert!(validate_slug("Has Space").is_err());
    }
}
