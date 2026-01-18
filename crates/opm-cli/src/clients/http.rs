// SPDX-License-Identifier: PMPL-1.0

use anyhow::{Context, Result};
use reqwest::blocking::Client;
use reqwest::header::{HeaderMap, HeaderValue, AUTHORIZATION, CONTENT_TYPE};

pub fn post_json(base: &str, path: &str, token: Option<&str>, body: &str) -> Result<()> {
    let client = Client::new();
    let mut headers = HeaderMap::new();
    headers.insert(CONTENT_TYPE, HeaderValue::from_static("application/json"));

    if let Some(token) = token {
        let value = format!("Bearer {token}");
        headers.insert(AUTHORIZATION, HeaderValue::from_str(&value)?);
    }

    let url = format!("{}{}", base.trim_end_matches('/'), path);
    let resp = client
        .post(url)
        .headers(headers)
        .body(body.to_string())
        .send()
        .context("opm http post")?;

    if !resp.status().is_success() {
        return Err(anyhow::anyhow!("http error: {}", resp.status()));
    }

    Ok(())
}
