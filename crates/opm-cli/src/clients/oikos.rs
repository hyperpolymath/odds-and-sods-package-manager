// SPDX-License-Identifier: PMPL-1.0

use anyhow::Result;

use crate::clients::http;

pub fn score(package: &str, base_url: &str, token: Option<&str>, opts: &http::HttpOptions) -> Result<()> {
    let body = format!("{\"package\":\"{package}\"}");
    http::post_json(base_url, "/score", token, &body, opts)
}
