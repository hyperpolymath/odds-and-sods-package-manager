// SPDX-License-Identifier: PMPL-1.0

use anyhow::{Context, Result};
use reqwest::blocking::Client;
use reqwest::header::{HeaderMap, HeaderValue, AUTHORIZATION, CONTENT_TYPE};
use std::time::Duration;

#[derive(Debug, Clone)]
pub struct HttpOptions {
    pub timeout_ms: u64,
    pub retries: u32,
    pub backoff_ms: u64,
}

pub fn post_json(base: &str, path: &str, token: Option<&str>, body: &str, opts: &HttpOptions) -> Result<()> {
    let client = Client::builder()
        .timeout(Duration::from_millis(opts.timeout_ms))
        .build()
        .context("http client")?;
    let mut headers = HeaderMap::new();
    headers.insert(CONTENT_TYPE, HeaderValue::from_static("application/json"));

    if let Some(token) = token {
        let value = format!("Bearer {token}");
        headers.insert(AUTHORIZATION, HeaderValue::from_str(&value)?);
    }

    let url = format!("{}{}", base.trim_end_matches('/'), path);
    let attempts = opts.retries.saturating_add(1);
    for attempt in 0..attempts {
        let resp = client
            .post(url.clone())
            .headers(headers.clone())
            .body(body.to_string())
            .send();

        match resp {
            Ok(resp) => {
                let status = resp.status();
                if status.is_success() {
                    return Ok(());
                }
                if attempt + 1 == attempts {
                    return Err(anyhow::anyhow!("http error: {status}"));
                }
            }
            Err(err) => {
                if attempt + 1 == attempts {
                    return Err(anyhow::anyhow!("http error: {err}"));
                }
            }
        }

        std::thread::sleep(Duration::from_millis(opts.backoff_ms * (attempt as u64 + 1)));
    }
    Ok(())
}
