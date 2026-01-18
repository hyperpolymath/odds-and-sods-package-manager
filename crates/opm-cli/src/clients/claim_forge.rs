// SPDX-License-Identifier: PMPL-1.0

use anyhow::Result;

use crate::clients::http;

pub fn attest(path: &str, base_url: &str, token: Option<&str>) -> Result<()> {
    let body = format!("{{\"path\":\"{path}\"}}");
    http::post_json(base_url, "/attest", token, &body)
}
