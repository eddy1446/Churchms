//! Shared types used across ChurchMS crates.
//!
//! Nothing in here should depend on HTTP, database, or any I/O.

use serde::{Deserialize, Serialize};
use uuid::Uuid;

/// A Church (tenant) in the system.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Church {
    pub id: Uuid,
    pub name: String,
    pub slug: String,
}

/// Minimal health payload returned by the API.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Health {
    pub status: String,
    pub version: String,
  }
