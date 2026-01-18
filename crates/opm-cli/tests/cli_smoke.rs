// SPDX-License-Identifier: PMPL-1.0

use assert_cmd::Command;

#[test]
fn help_runs() {
    let mut cmd = Command::cargo_bin("opm").expect("binary builds");
    cmd.arg("--help");
    cmd.assert().success();
}
