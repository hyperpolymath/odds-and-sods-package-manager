// SPDX-License-Identifier: PMPL-1.0

use anyhow::Result;

use crate::clients;
use crate::config::OpmConfig;

pub fn publish(path: &str) -> Result<()> {
    println!("opm publish (stub) for {path}");
    let cfg = OpmConfig::load_from("opm.toml").unwrap_or_else(|_| OpmConfig::example());
    clients::claim_forge::attest(path, &cfg.claim_forge.base_url, cfg.claim_forge.token.as_deref())?;
    clients::checky_monkey::analyze(path, &cfg.checky_monkey.base_url, cfg.checky_monkey.token.as_deref())?;
    clients::palimpsest_license::audit(path, &cfg.palimpsest_license.base_url, cfg.palimpsest_license.token.as_deref())?;
    clients::cicd_hyper_a::publish(path, &cfg.cicd_hyper_a.base_url, cfg.cicd_hyper_a.token.as_deref())?;
    Ok(())
}

pub fn audit(package: &str) -> Result<()> {
    println!("opm audit (stub) for {package}");
    let cfg = OpmConfig::load_from("opm.toml").unwrap_or_else(|_| OpmConfig::example());
    clients::claim_forge::attest(package, &cfg.claim_forge.base_url, cfg.claim_forge.token.as_deref())?;
    clients::checky_monkey::analyze(package, &cfg.checky_monkey.base_url, cfg.checky_monkey.token.as_deref())?;
    clients::oikos::score(package, &cfg.oikos.base_url, cfg.oikos.token.as_deref())?;
    Ok(())
}

pub fn status() -> Result<()> {
    println!("opm status (stub)");
    println!("- federation: git-private-farm + Radicle + IPFS");
    println!("- registry: opm-registry-hub");
    Ok(())
}
