# SPDX-License-Identifier: PMPL-1.0
defmodule Opm.RegistryGatewayTest do
  use ExUnit.Case

  alias Opm.RegistryGateway

  setup do
    Opm.RegistryGateway.Store.reset()
    :ok
  end

  test "publish stores manifest information and is retrievable" do
    manifest = %{"name" => "example", "version" => "1.2.3"}
    imm = %{"name" => "example", "license" => "MIT"}
    digest = "sha256:abcd"

    assert {:ok, entry} = RegistryGateway.publish(manifest, imm, digest)
    assert entry.digest == digest

    assert {:ok, fetched} = RegistryGateway.fetch_package("example")
    assert fetched.digest == digest
    assert fetched.manifest["name"] == "example"
  end

  test "handle_publish rejects invalid payload" do
    assert {:error, _} = RegistryGateway.handle_publish(%{"foo" => "bar"})
  end
end
