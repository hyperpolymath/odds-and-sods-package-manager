// SPDX-License-Identifier: PMPL-1.0

use assert_cmd::cargo::cargo_bin_cmd;

#[test]
fn help_runs() {
    let mut cmd = cargo_bin_cmd!("opm");
    cmd.arg("--help");
    cmd.assert().success();
}
