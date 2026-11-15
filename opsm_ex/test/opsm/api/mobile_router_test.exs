# SPDX-License-Identifier: MPL-2.0
defmodule Opsm.Api.MobileRouterTest do
  use ExUnit.Case, async: true

  import Plug.Test

  alias Opsm.Api.MobileRouter
  alias Opsm.Package.Installer

  test "capabilities identify the implemented read-only subset" do
    response = request(:get, "/api/capabilities")
    assert response.status == 200

    operations = Jason.decode!(response.resp_body)["operations"]
    assert operations["installed"] == "available_read_only"
    assert operations["install"] == "unavailable"
    assert operations["search"] == "unavailable"
    assert operations["package_info"] == "unavailable"
    assert operations["audit_lockfile"] == "unavailable"
  end

  test "install endpoint cannot fabricate installation success" do
    payload = Jason.encode!(%{name: "react", registry: "npm", version: "18.2.0"})
    response = request(:post, "/api/packages/install", payload)

    assert response.status == 501
    assert Jason.decode!(response.resp_body) == %{
             "error" => "not_implemented",
             "operation" => "install",
             "status" => "unavailable"
           }
  end

  test "search never returns hard-coded registry hits" do
    response = request(:get, "/api/packages/search?q=react")

    assert response.status == 501
    assert Jason.decode!(response.resp_body)["operation"] == "search"
  end

  test "package details do not return fictitious provenance" do
    response = request(:get, "/api/packages/react/18.2.0")

    assert response.status == 501
    result = Jason.decode!(response.resp_body)
    assert result["operation"] == "package_info"
    assert result["requested"] == %{"name" => "react", "version" => "18.2.0"}
  end

  test "installed packages reflect the real local installed-state reader" do
    response = request(:get, "/api/packages/installed")
    assert response.status == 200
    assert Jason.decode!(response.resp_body) == Installer.list_installed()
  end

  test "audit endpoint must not invent vulnerability scores" do
    response = request(:post, "/api/audit/lockfile", "{}")
    assert response.status == 501
    assert Jason.decode!(response.resp_body)["operation"] == "audit_lockfile"
  end

  test "health is not an installation success claim" do
    response = request(:get, "/api/health")

    assert response.status == 200
    result = Jason.decode!(response.resp_body)
    assert result["service"] == "opsm-mobile-api"
    assert result["capability_discovery"] == "/api/capabilities"
  end

  test "responses are JSON with no-store and nosniff" do
    response = request(:get, "/api/capabilities")

    assert Plug.Conn.get_resp_header(response, "cache-control") == ["no-store"]
    assert Plug.Conn.get_resp_header(response, "x-content-type-options") == ["nosniff"]
    assert Plug.Conn.get_resp_header(response, "content-type") == ["application/json; charset=utf-8"]
  end

  defp request(method, path, body \\ "") do
    conn(method, path, body)
    |> Plug.Conn.put_req_header("content-type", "application/json")
    |> MobileRouter.call(MobileRouter.init([]))
  end
end
