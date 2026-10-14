mod config;
mod db;

use axum::{extract::State, routing::get, Json, Router};
use churchms_shared::Health;
use sqlx::PgPool;
use std::net::SocketAddr;
use tower_http::trace::TraceLayer;
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

use crate::config::Config;

#[derive(Clone)]
pub struct AppState {
    pub pool: PgPool,
    pub config: Config,
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // Load .env before anything else so RUST_LOG works below.
    let _ = dotenvy::dotenv();

    let config = Config::from_env()?;

    tracing_subscriber::registry()
        .with(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "info,churchms_api=debug,tower_http=debug".into()),
        )
        .with(tracing_subscriber::fmt::layer())
        .init();

    tracing::info!(app_env = %config.app_env, "starting ChurchMS API");

    tracing::info!("connecting to database");
    let pool = db::connect(&config.database_url).await?;

    tracing::info!("running migrations");
    db::run_migrations(&pool).await?;
    tracing::info!("migrations up to date");

    let state = AppState {
        pool,
        config: config.clone(),
    };

    let app = Router::new()
        .route("/health", get(health))
        .layer(TraceLayer::new_for_http())
        .with_state(state);

    let addr: SocketAddr = format!("{}:{}", config.host, config.port).parse()?;
    tracing::info!("listening on {addr}");

    let listener = tokio::net::TcpListener::bind(addr).await?;
    axum::serve(listener, app).await?;

    Ok(())
}

/// Health check. Verifies the API is up **and** the database is reachable.
async fn health(State(state): State<AppState>) -> Json<Health> {
    let db_ok = sqlx::query_scalar::<_, i32>("SELECT 1")
        .fetch_one(&state.pool)
        .await
        .is_ok();

    Json(Health {
        status: if db_ok { "ok" } else { "degraded" }.to_string(),
        version: env!("CARGO_PKG_VERSION").to_string(),
    })
}
