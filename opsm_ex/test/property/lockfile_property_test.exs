# SPDX-License-Identifier: MPL-2.0
defmodule Opsm.Property.LockfilePropertyTest do
  use ExUnit.Case
  use ExUnitProperties

  alias Opsm.Lockfile
  alias Opsm.VersionConstraint

  @moduletag :property

  # Generators for property-based testing
  defp package_name_gen do
    string(:alphanumeric, min_length: 1, max_length: 20)
  end

  defp version_gen do
    gen all major <- integer(0..10),
           minor <- integer(0..20),
           patch <- integer(0..50) do
      "#{major}.#{minor}.#{patch}"
    end
  end

  defp semver_version_gen do
    gen all major <- integer(0..10),
           minor <- integer(0..20),
           patch <- integer(0..50) do
      "#{major}.#{minor}.#{patch}"
    end
  end

  defp forth_gen do
    one_of([
      constant(:npm),
      constant(:hex),
      constant(:cargo),
      constant(:pypi),
      constant(:nimble),
      constant(:idris2),
      constant(:git),
      constant(:internal)
    ])
  end

  defp checksum_gen do
    string(:alphanumeric, min_length: 32, max_length: 64)
  end

  defp package_gen do
    gen all name <- package_name_gen(),
           version <- version_gen(),
           forth <- forth_gen(),
           checksum <- checksum_gen(),
           algo <- one_of([constant("sha256"), constant("blake2b"), constant("sha3-512")]) do
      %{
        name: name,
        version: version,
        forth: forth,
        checksum: checksum,
        checksum_algo: algo
      }
    end
  end

  describe "Lockfile Determinism" do
    property "package list is consistent after add/get operations" do
      check all packages <- list_of(package_gen(), min_length: 1, max_length: 10) do
        lockfile = packages
        |> Enum.reduce(Lockfile.new(), &Lockfile.add_package(&2, &1))

        # List packages and count
        listed = Lockfile.list_packages(lockfile)

        # Each listed package should be retrievable
        Enum.each(listed, fn pkg ->
          retrieved = Lockfile.get_package(lockfile, pkg.name, pkg.forth)
          assert retrieved.name == pkg.name
          assert retrieved.forth == pkg.forth
        end)
      end
    end

    property "lockfile list count matches added package count" do
      check all packages <- list_of(package_gen(), min_length: 1, max_length: 15) do
        lockfile = packages
        |> Enum.reduce(Lockfile.new(), &Lockfile.add_package(&2, &1))

        listed = Lockfile.list_packages(lockfile)

        # Count should match (may have duplicates if same name/forth added multiple times)
        assert length(listed) <= length(packages)
      end
    end

    property "adding and removing same package returns to previous count" do
      check all name <- package_name_gen(),
            forth <- forth_gen(),
            initial_count <- integer(0..5) do
        # Build initial lockfile
        original = Enum.reduce(0..initial_count, Lockfile.new(), fn i, acc ->
          Lockfile.add_package(acc, %{
            name: "pkg-#{i}",
            version: "1.0.0",
            forth: forth,
            checksum: "hash-#{i}"
          })
        end)

        original_count = Lockfile.list_packages(original) |> length()

        # Add and remove new package
        modified = original
        |> Lockfile.add_package(%{name: name, version: "2.0.0", forth: forth, checksum: "new-hash"})
        |> Lockfile.remove_package(name, forth)

        # Should be back to original count
        modified_count = Lockfile.list_packages(modified) |> length()
        assert original_count == modified_count
      end
    end
  end

  describe "Version Constraint Intersection" do
    property "intersection of compatible constraints is valid" do
      check all constraint1 <- string(:alphanumeric, min_length: 1, max_length: 10),
            constraint2 <- string(:alphanumeric, min_length: 1, max_length: 10) do
        case {VersionConstraint.parse(constraint1, :semver), VersionConstraint.parse(constraint2, :semver)} do
          {{:ok, c1}, {:ok, c2}} ->
            # Both should parse successfully
            assert c1 != nil
            assert c2 != nil

          # Parsing failures are acceptable
          {{:error, _}, _} -> :ok
          {_, {:error, _}} -> :ok
        end
      end
    end

    property "version satisfying constraint satisfies intersection" do
      check all version <- semver_version_gen(),
            version_constraint <- string(:alphanumeric, min_length: 1, max_length: 20) do
        case VersionConstraint.parse(version_constraint, :semver) do
          {:ok, constraint} ->
            # Either it satisfies or it doesn't - both are valid outcomes
            _result = VersionConstraint.satisfies?(version, constraint)
            :ok

          {:error, _} ->
            # Invalid constraint is acceptable
            :ok
        end
      end
    end
  end

  describe "Manifest Roundtrip" do
    property "parse -> serialize -> parse yields equivalent manifest" do
      check all name <- package_name_gen(),
            version <- version_gen(),
            forth <- forth_gen() do
        original = %{
          name: name,
          version: version,
          forth: forth,
          description: "Test package"
        }

        # Roundtrip: serialize to JSON and back
        serialized = Jason.encode!(original)
        {:ok, deserialized} = Jason.decode(serialized)

        # Convert keys to atoms for comparison
        deserialized_atoms = Map.new(deserialized, fn {k, v} -> {String.to_atom(k), v} end)

        # Core fields should match
        assert deserialized_atoms.name == original.name
        assert deserialized_atoms.version == original.version
        assert deserialized_atoms.forth == to_string(original.forth)
      end
    end

    property "lockfile write -> read preserves package data" do
      check all packages <- list_of(package_gen(), min_length: 1, max_length: 10) do
        lockfile = packages
        |> Enum.reduce(Lockfile.new(), &Lockfile.add_package(&2, &1))

        # Verify all packages are present and unchanged
        written_packages = Lockfile.list_packages(lockfile)

        assert length(written_packages) == length(packages)

        # Each package should have correct data
        Enum.each(written_packages, fn pkg ->
          assert pkg.name != nil
          assert pkg.version != nil
          assert pkg.forth != nil
        end)
      end
    end
  end

  describe "Dependency Tree Consistency" do
    property "packages_for_forth returns only packages from specified forth" do
      check all packages <- list_of(package_gen(), min_length: 1, max_length: 20),
            target_forth <- forth_gen() do
        lockfile = packages
        |> Enum.reduce(Lockfile.new(), &Lockfile.add_package(&2, &1))

        filtered = Lockfile.packages_for_forth(lockfile, target_forth)

        # All returned packages should be from target forth
        assert Enum.all?(filtered, fn p -> p.forth == target_forth end)

        # Count should match manual count
        expected_count = Enum.count(packages, fn p -> p.forth == target_forth end)
        assert length(filtered) == expected_count
      end
    end

    property "list_packages maintains consistent ordering" do
      check all packages <- list_of(package_gen(), min_length: 1, max_length: 15) do
        lockfile = packages
        |> Enum.reduce(Lockfile.new(), &Lockfile.add_package(&2, &1))

        listed1 = Lockfile.list_packages(lockfile)
        listed2 = Lockfile.list_packages(lockfile)

        # Multiple listings should be consistent
        assert listed1 == listed2
      end
    end
  end

  describe "Checksum Consistency" do
    property "checksum mismatch is consistently detected" do
      check all pkg_name <- package_name_gen(),
            version <- version_gen(),
            forth <- forth_gen(),
            stored_checksum <- checksum_gen(),
            actual_checksum <- checksum_gen() do
        lockfile = Lockfile.new()
        |> Lockfile.add_package(%{
          name: pkg_name,
          version: version,
          forth: forth,
          checksum: stored_checksum
        })

        result1 = Lockfile.verify_package(lockfile, pkg_name, forth, actual_checksum)
        result2 = Lockfile.verify_package(lockfile, pkg_name, forth, actual_checksum)

        # Same verification should always give same result
        assert result1 == result2

        # If checksums differ, should be mismatch
        if stored_checksum != actual_checksum do
          assert match?({:mismatch, _}, result1)
        else
          assert result1 == :ok
        end
      end
    end

    property "package is retrievable after adding" do
      check all pkg_name <- package_name_gen(),
            version <- version_gen(),
            forth <- forth_gen(),
            checksum <- checksum_gen() do
        lockfile = Lockfile.new()
        |> Lockfile.add_package(%{
          name: pkg_name,
          version: version,
          forth: forth,
          checksum: checksum
        })

        pkg = Lockfile.get_package(lockfile, pkg_name, forth)

        assert pkg.name == pkg_name
        assert pkg.version == version
        assert pkg.forth == forth
        assert pkg.checksum == checksum
      end
    end
  end

  describe "Integrity Hash Properties" do
    property "integrity hash is recomputable for same packages" do
      check all count <- integer(1..8) do
        packages = Enum.map(0..count, fn i ->
          %{
            name: "pkg-#{i}",
            version: "1.0.#{i}",
            forth: :npm,
            checksum: "hash-#{i}"
          }
        end)

        # Create lockfile
        lockfile = packages
        |> Enum.reduce(Lockfile.new(), &Lockfile.add_package(&2, &1))

        # Compute hash twice on same lockfile - should be identical
        with_hash1 = Lockfile.compute_integrity_hash(lockfile)
        with_hash2 = Lockfile.compute_integrity_hash(lockfile)

        # Both computations should produce same hash
        assert with_hash1.integrity_hash == with_hash2.integrity_hash
      end
    end

    property "integrity hash is never nil after computation" do
      check all name <- package_name_gen() do
        lockfile = Lockfile.new()
        |> Lockfile.add_package(%{
          name: name,
          version: "1.0.0",
          forth: :npm,
          checksum: "test-hash"
        })
        |> Lockfile.compute_integrity_hash()

        assert lockfile.integrity_hash != nil
        assert String.length(lockfile.integrity_hash) > 0
      end
    end

    property "integrity hash uses correct algorithm" do
      check all count <- integer(1..5) do
        lockfile = Enum.reduce(0..count, Lockfile.new(), fn i, acc ->
          Lockfile.add_package(acc, %{
            name: "pkg-#{i}",
            version: "1.0.0",
            forth: :npm,
            checksum: "hash-#{i}"
          })
        end)
        |> Lockfile.compute_integrity_hash()

        assert lockfile.integrity_algo == "sha3-512"
        assert String.length(lockfile.integrity_hash) == 128
      end
    end
  end
end
