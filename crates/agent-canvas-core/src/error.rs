use thiserror::Error;

pub type Result<T> = std::result::Result<T, Error>;

#[derive(Debug, Error)]
pub enum Error {
    #[error("unknown canvas id: {0} (expected size-first id like sm-one)")]
    UnknownCanvas(String),

    #[error("schema validation failed: {0}")]
    Validation(String),

    #[error("io error: {0}")]
    Io(#[from] std::io::Error),

    #[error("json error: {0}")]
    Json(#[from] serde_json::Error),

    #[error("invalid slug: {0}")]
    InvalidSlug(String),

    #[error("cloud API config: {0}")]
    CloudConfig(String),

    #[error("cloud API HTTP {status}: {message}")]
    CloudHttp { status: u16, message: String },

    #[error("cloud API transport: {0}")]
    CloudTransport(String),

    #[error("edit token missing for slug `{0}` — share again or pass edit_token")]
    MissingEditToken(String),

    #[error("credential store: {0}")]
    CredentialStore(String),

    #[error("share not found: {0}")]
    ShareNotFound(String),
}
