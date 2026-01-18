// SPDX-License-Identifier: PMPL-1.0

use anyhow::Result;

pub fn attest(_path: &str) -> Result<()> {
    // TODO: call claim-forge service (GPG + OpenTimestamps)
    Ok(())
}
