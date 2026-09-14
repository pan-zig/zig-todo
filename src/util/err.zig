//! Shared application errors.

pub const Error = error{
    InvalidArgs,
    NotFound,
    ValidationFailed,
    EmptyText,
    TextTooLong,
    InvalidId,
    CorruptData,
    UnsupportedVersion,
    IoError,
};
