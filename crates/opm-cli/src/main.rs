use clap::{Parser, Subcommand};

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
        Commands::Publish { path } => {
            println!("publish pipeline (stub) for {path}");
        }
        Commands::Audit { package } => {
            println!("audit pipeline (stub) for {package}");
        }
        Commands::Status => {
            println!("opm status (stub)");
        }
    }

    Ok(())
}
