//! Database pool creation and migration runner.

use sqlx::postgres::{PgPool, PgPoolOptions};
use std::time::Duration;

/// Create a connection pool to Postgres.
///
/// Pool sizing notes:
/// - `max_connections`: cap concurrent DB connections. Postgres default max is
///   100; keep this low so you can run multiple services later.
/// - `min_connections`: keep warm connections so the first request isn't slow.
/// - `acquire_timeout`: fail fast if the pool is exhausted — surfaces bugs.
pub async fn connect(database_url: &str) -> anyhow::Result<PgPool> {
    let pool = PgPoolOptions::new()
        .max_connections(10)
        .min_connections(1)
        .acquire_timeout(Duration::from_secs(5))
        .idle_timeout(Duration::from_secs(600))
        .connect(database_url)
        .await?;

    Ok(pool)
}

/// Run all pending migrations from `backend/migrations/`.
///
/// The `migrate!` macro reads the migrations directory at **compile time**
/// and embeds the SQL into the binary. So production doesn't need the
/// migration files on disk — the binary is self-contained.
pub async fn run_migrations(pool: &PgPool) -> anyhow::Result<()> {
    sqlx::migrate!("../../migrations").run(pool).await?;
    Ok(())
}
