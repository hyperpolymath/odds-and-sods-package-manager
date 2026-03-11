;; SPDX-License-Identifier: PMPL-1.0-or-later
(bot-directive
  (bot "echidnabot")
  (scope "formal verification, fuzzing, and property-based testing")
  (languages ("Rust" "Elixir" "ReScript"))
  (targets
    ("services/*/src/" "Rust service binaries")
    ("opsm_ex/" "Elixir application and NIFs")
    ("cli/" "CLI tooling"))
  (allow ("analysis" "fuzzing" "proof checks" "property testing" "unsafe auditing"))
  (deny ("write to core modules" "write to bindings" "modify Cargo.lock"))
  (scanning-rules
    (rust
      (ban ("unsafe" "transmute") (unless "// SAFETY: comment present"))
      (flag ("unwrap" "expect") (severity "medium")))
    (elixir
      (flag ("Code.eval_string" "apply/3 with dynamic module") (severity "high"))))
  (notes "May open findings; code changes require explicit approval"))
