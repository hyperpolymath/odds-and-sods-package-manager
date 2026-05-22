# SPDX-License-Identifier: MPL-2.0
defmodule Opsm.RegistryGateway do
  @moduledoc """
  Minimal http-capability-gateway for registry operations.
  """

  alias Opsm.RegistryGateway.Store

  @spec publish(map(), map(), String.t()) :: {:ok, map()}
  def publish(manifest, imp, digest) do
    manifest_map = normalize_manifest(manifest)
    name = manifest_map["name"]
    entry = %{
      manifest: manifest_map,
      imp: imp,
      digest: digest,
      published_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    {:ok, Store.publish(name, entry)}
  end

  @spec handle_publish(map()) :: {:ok, map()} | {:error, String.t()}
  def handle_publish(%{"manifest" => manifest, "imp" => imp, "digest" => digest}) do
    publish(manifest, imp, digest)
  end

  def handle_publish(_), do: {:error, "invalid payload"}

  @spec fetch_package(String.t()) :: {:ok, map()} | :error
  def fetch_package(name) do
    Store.fetch(name)
  end

  @spec list_packages() :: map()
  def list_packages do
    Store.list_all()
  end

  defp normalize_manifest(manifest) when is_struct(manifest) do
    manifest
    |> Map.from_struct()
    |> Map.delete(:__struct__)
  end

  defp normalize_manifest(manifest) when is_map(manifest), do: manifest
end
