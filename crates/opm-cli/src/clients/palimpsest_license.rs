// SPDX-License-Identifier: PMPL-1.0

use anyhow::Result;

use crate::clients::http;

pub fn audit(path: &str, base_url: &str, token: Option<&str>, opts: &http::HttpOptions) -> Result<()> {
    let body = serde_json::json!({ "path": path }).to_string();
    http::post_json(base_url, "/audit", token, &body, opts)
}
