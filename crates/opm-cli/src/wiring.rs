// SPDX-License-Identifier: PMPL-1.0

use anyhow::Result;

use crate::clients;

pub fn publish(path: &str) -> Result<()> {
    println!("opm publish (stub) for {path}");
    clients::claim_forge::attest(path)?;
    clients::checky_monkey::analyze(path)?;
    clients::palimpsest_license::audit(path)?;
    clients::cicd_hyper_a::publish(path)?;
    Ok(())
}

pub fn audit(package: &str) -> Result<()> {
    println!("opm audit (stub) for {package}");
    clients::claim_forge::attest(package)?;
    clients::checky_monkey::analyze(package)?;
    clients::oikos::score(package)?;
    Ok(())
}

pub fn status() -> Result<()> {
    println!("opm status (stub)");
    println!("- federation: git-private-farm + Radicle + IPFS");
    println!("- registry: opm-registry-hub");
    Ok(())
}
