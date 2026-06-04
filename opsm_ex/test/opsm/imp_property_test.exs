# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.ImpPropertyTest do
  use ExUnit.Case
  use ExUnitProperties

  alias Opsm.Imp
  alias Opsm.Types.ManifestFormat

  property "IMP normalization succeeds for manifests with required fields" do
    check all manifest <- manifest_with_dependencies() do
      digest = "sha256:" <> Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)

      assert {:ok, normalized} =
               Imp.normalize(manifest, "/tmp/#{manifest.name}.json", digest)

      assert normalized["name"] == manifest.name
      assert normalized["dependencies"] |> Enum.count() == map_size(manifest.dependencies)
    end
  end

  property "IMP normalization rejects missing required fields" do
    check all manifest <- manifest_missing_license() do
      digest = "sha256:" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)

      assert {:error, message} = Imp.normalize(manifest, "/tmp/missing.json", digest)
      assert message =~ "IMP requires"
    end
  end

  property "IMP normalization rejects manifests with zero dependencies" do
    check all manifest <- manifest_without_dependencies() do
      digest = "sha256:" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)

      assert {:error, message} = Imp.normalize(manifest, "/tmp/nop.json", digest)
      assert message =~ "requires at least one dependency"
    end
  end

  defp manifest_with_dependencies do
    gen all name <- string(:alphanumeric, min_length: 1),
            version <- string(:alphanumeric, min_length: 1),
            license <- string(:alphanumeric, min_length: 1),
            dependency <- dependency_pair() do
      %ManifestFormat{
        name: name,
        version: version,
        license: license,
        dependencies: Map.new([{dependency.name, dependency.version}])
      }
    end
  end

  defp manifest_missing_license do
    gen all name <- string(:alphanumeric, min_length: 1),
            version <- string(:alphanumeric, min_length: 1) do
      %ManifestFormat{
        name: name,
        version: version,
        license: nil,
        dependencies: %{"dep" => "1.0.0"}
      }
    end
  end

  defp manifest_without_dependencies do
    gen all name <- string(:alphanumeric, min_length: 1),
            version <- string(:alphanumeric, min_length: 1),
            license <- string(:alphanumeric, min_length: 1) do
      %ManifestFormat{
        name: name,
        version: version,
        license: license,
        dependencies: %{}
      }
    end
  end

  defp dependency_pair do
    gen all name <- string(:alphanumeric, min_length: 1),
            version <- string(:alphanumeric, min_length: 1) do
      %{name: name, version: version}
    end
  end
end
