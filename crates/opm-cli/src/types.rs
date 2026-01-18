// SPDX-License-Identifier: PMPL-1.0

#![allow(dead_code)]

use serde::{Deserialize, Serialize};

#[derive(Debug, Serialize, Deserialize)]
pub struct PublishRequest {
    pub path: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct AuditRequest {
    pub package: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct StatusResponse {
    pub registry_hub: String,
    pub federation: String,
}
