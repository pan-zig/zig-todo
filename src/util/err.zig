//! Shared application errors.

pub const Error = error{
    InvalidArgs,
    NotFound,
    ValidationFailed,
    EmptyText,
    TextTooLong,
    EmptyTag,
    TagTooLong,
    TooManyTags,
    InvalidId,
    CorruptData,
    UnsupportedVersion,
    IoError,
};
