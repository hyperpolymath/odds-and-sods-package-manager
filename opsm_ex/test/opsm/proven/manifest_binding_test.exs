# SPDX-License-Identifier: MPL-2.0
defmodule Opsm.Proven.ManifestBindingTest do
  use ExUnit.Case, async: true

  alias Opsm.Proven.ManifestBinding

  test "accepts an exact module-to-file evidence declaration" do
    declared = [%{"module" => "Opsm.SampleTest", "file" => "test/sample_test.exs"}]
    observed = [%{module: "Opsm.SampleTest", file: "test/sample_test.exs"}]

    assert ManifestBinding.violations(declared, observed) == []
  end

  test "rejects a plausible existing path that does not define the claimed module" do
    declared = [%{"module" => "Opsm.SampleTest", "file" => "test/other_test.exs"}]
    observed = [%{module: "Opsm.SampleTest", file: "test/sample_test.exs"}]

    assert [problem] = ManifestBinding.violations(declared, observed)
    assert problem =~ "test/other_test.exs"
    assert problem =~ "test/sample_test.exs"
  end

  test "refuses ambiguous duplicate module definitions" do
    declared = [%{"module" => "Opsm.SampleTest", "file" => "test/sample_test.exs"}]

    observed = [
      %{module: "Opsm.SampleTest", file: "test/sample_test.exs"},
      %{module: "Opsm.SampleTest", file: "test/shadow_test.exs"}
    ]

    assert [problem] = ManifestBinding.violations(declared, observed)
    assert problem =~ "ambiguous source definitions"
  end

  test "leaves absent modules to the caller's stale-entry validator" do
    declared = [%{"module" => "Opsm.MissingTest", "file" => "test/missing_test.exs"}]
    assert ManifestBinding.violations(declared, []) == []
  end
end
