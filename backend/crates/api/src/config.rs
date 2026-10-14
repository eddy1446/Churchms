//! Typed application configuration loaded from environment variables.

use anyhow::{anyhow, Context};
use std::env;
use uuid::Uuid;

#[derive(Debug, Clone)]
pub struct Config {
    pub database_url: String,
    pub host: String,
    pub port: u16,
    pub jwt_secret: String,
    pub jwt_access_ttl_minutes: i64,
    pub jwt_refresh_ttl_days: i64,
    pub app_env: String,
    pub default_church_id: Uuid,
}

impl Config {
    /// Load config from environment. `.env` must already be loaded.
    pub fn from_env() -> anyhow::Result<Self> {
        let database_url = env::var("DATABASE_URL")
            .context("DATABASE_URL must be set (see backend/.env.example)")?;

        let jwt_secret =
            env::var("JWT_SECRET").context("JWT_SECRET must be set (see backend/.env.example)")?;

        if jwt_secret.len() < 32 {
            return Err(anyhow!(
                "JWT_SECRET must be at least 32 chars; generate with `openssl rand -base64 48`"
            ));
        }

        let host = env::var("API_HOST").unwrap_or_else(|_| "0.0.0.0".into());

        let port = env::var("API_PORT")
            .ok()
            .and_then(|s| s.parse::<u16>().ok())
            .unwrap_or(8080);

        let jwt_access_ttl_minutes = env::var("JWT_ACCESS_TTL_MINUTES")
            .ok()
            .and_then(|s| s.parse().ok())
            .unwrap_or(15);

        let jwt_refresh_ttl_days = env::var("JWT_REFRESH_TTL_DAYS")
            .ok()
            .and_then(|s| s.parse().ok())
            .unwrap_or(30);

        let app_env = env::var("APP_ENV").unwrap_or_else(|_| "development".into());

        let default_church_id = env::var("DEFAULT_CHURCH_ID")
            .context("DEFAULT_CHURCH_ID must be set")?
            .parse::<Uuid>()
            .context("DEFAULT_CHURCH_ID must be a valid UUID")?;

        Ok(Self {
            database_url,
            host,
            port,
            jwt_secret,
            jwt_access_ttl_minutes,
            jwt_refresh_ttl_days,
            app_env,
            default_church_id,
        })
    }

    pub fn is_dev(&self) -> bool {
        self.app_env == "development"
    }
  }
