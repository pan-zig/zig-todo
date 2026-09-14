//! ID allocation helpers.

/// Next id after scanning existing items (self-heal if next_id lags).
pub fn healNextId(next_id: u64, max_existing_id: u64) u64 {
    if (max_existing_id == 0) return @max(next_id, 1);
    return @max(next_id, max_existing_id + 1);
}
