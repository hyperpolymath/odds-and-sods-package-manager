// SPDX-License-Identifier: PMPL-1.0

use serde::Deserialize;
use std::fs;
use std::path::Path;

#[derive(Debug, Deserialize, Clone)]
pub struct ServiceConfig {
    pub base_url: String,
    pub token: Option<String>,
}

#[derive(Debug, Deserialize, Clone)]
pub struct OpmConfig {
    pub claim_forge: ServiceConfig,
    pub checky_monkey: ServiceConfig,
    pub palimpsest_license: ServiceConfig,
    pub cicd_hyper_a: ServiceConfig,
    pub oikos: ServiceConfig,
}

impl OpmConfig {
    pub fn example() -> Self {
        Self {
            claim_forge: ServiceConfig {
                base_url: "http://127.0.0.1:7001".to_string(),
                token: None,
            },
            checky_monkey: ServiceConfig {
                base_url: "http://127.0.0.1:7002".to_string(),
                token: None,
            },
            palimpsest_license: ServiceConfig {
                base_url: "http://127.0.0.1:7003".to_string(),
                token: None,
            },
            cicd_hyper_a: ServiceConfig {
                base_url: "http://127.0.0.1:7004".to_string(),
                token: None,
            },
            oikos: ServiceConfig {
                base_url: "http://127.0.0.1:7005".to_string(),
                token: None,
            },
        }
    }

    pub fn load_from(path: impl AsRef<Path>) -> anyhow::Result<Self> {
        let data = fs::read_to_string(path)?;
        let cfg = toml::from_str(&data)?;
        Ok(cfg)
    }
}
