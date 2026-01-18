// SPDX-License-Identifier: PMPL-1.0

use serde::Deserialize;
use std::fs;
use std::path::Path;

#[derive(Debug, Deserialize, Clone)]
#[serde(default)]
pub struct HttpConfig {
    pub timeout_ms: u64,
    pub retries: u32,
    pub backoff_ms: u64,
}

impl Default for HttpConfig {
    fn default() -> Self {
        Self {
            timeout_ms: 3000,
            retries: 2,
            backoff_ms: 200,
        }
    }
}

#[derive(Debug, Deserialize, Clone)]
pub struct ServiceConfig {
    pub base_url: String,
    pub token: Option<String>,
}

#[derive(Debug, Deserialize, Clone)]
pub struct OpmConfig {
    #[serde(default)]
    pub http: HttpConfig,
    pub claim_forge: ServiceConfig,
    pub checky_monkey: ServiceConfig,
    pub palimpsest_license: ServiceConfig,
    pub cicd_hyper_a: ServiceConfig,
    pub oikos: ServiceConfig,
}

impl OpmConfig {
    pub fn example() -> Self {
        Self {
            http: HttpConfig::default(),
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

    pub fn load() -> anyhow::Result<Self> {
        if let Ok(path) = std::env::var("OPM_CONFIG") {
            return Self::load_from(path);
        }

        let local = Path::new("opm.toml");
        if local.exists() {
            return Self::load_from(local);
        }

        if let Ok(home) = std::env::var("HOME") {
            let path = Path::new(&home).join(".config/opm/opm.toml");
            if path.exists() {
                return Self::load_from(path);
            }
        }

        Err(anyhow::anyhow!("opm config not found"))
    }
}
