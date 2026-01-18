// SPDX-License-Identifier: PMPL-1.0

use clap::{Parser, Subcommand};

mod wiring;

#[derive(Parser)]
#[command(name = "opm")]
#[command(about = "Odds-and-sods package manager", long_about = None)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    Publish { path: String },
    Audit { package: String },
    Status,
}

fn main() -> anyhow::Result<()> {
    let cli = Cli::parse();

    match cli.command {
        Commands::Publish { path } => wiring::publish(&path)?,
        Commands::Audit { package } => wiring::audit(&package)?,
        Commands::Status => wiring::status()?,
    }

    Ok(())
}
