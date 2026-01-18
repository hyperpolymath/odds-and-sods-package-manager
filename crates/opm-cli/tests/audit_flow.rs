// SPDX-License-Identifier: PMPL-1.0

use assert_cmd::cargo::cargo_bin_cmd;
use mockito::Server;
use std::io::Write;
use tempfile::NamedTempFile;

#[test]
fn audit_hits_pipeline_endpoints() {
    let mut server = Server::new();

    let _attest = server.mock("POST", "/attest").with_status(200).create();
    let _analyze = server.mock("POST", "/analyze").with_status(200).create();
    let _score = server.mock("POST", "/score").with_status(200).create();

    let mut file = NamedTempFile::new().expect("tmp config");
    let cfg = format!(
        "[http]\nretries = 0\n\n[claim_forge]\nbase_url = \"{}\"\n\n[checky_monkey]\nbase_url = \"{}\"\n\n[palimpsest_license]\nbase_url = \"{}\"\n\n[cicd_hyper_a]\nbase_url = \"{}\"\n\n[oikos]\nbase_url = \"{}\"\n",
        server.url(),
        server.url(),
        server.url(),
        server.url(),
        server.url()
    );
    file.write_all(cfg.as_bytes()).expect("write config");

    let mut cmd = cargo_bin_cmd!("opm");
    cmd.env("OPM_CONFIG", file.path());
    cmd.arg("audit").arg("example-lib");
    cmd.assert().success();
}
