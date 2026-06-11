# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Crypto.ApiKeyStorageTest do
  use ExUnit.Case, async: true
  alias Opsm.Crypto.ApiKeyStorage

  setup do
    # Use a temporary directory for each test
    tmp_dir = Path.join(System.tmp_dir!(), "opsm_api_keys_test_#{:rand.uniform(1_000_000)}")
    File.mkdir_p!(tmp_dir)
    storage_path = Path.join(tmp_dir, "api_keys.json")

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    {:ok, storage_path: storage_path}
  end

  describe "generate_master_key/0" do
    test "generates 256-bit master key" do
      master_key = ApiKeyStorage.generate_master_key()
      assert byte_size(master_key) == 32  # 256 bits
    end

    test "generates different keys each time" do
      key1 = ApiKeyStorage.generate_master_key()
      key2 = ApiKeyStorage.generate_master_key()
      assert key1 != key2
    end
  end

  describe "generate_token/1" do
    test "generates tokens of specified length" do
      token = ApiKeyStorage.generate_token(32)
      # Base64 URL-safe encoding, no padding
      assert is_binary(token)
      assert String.length(token) > 0
    end

    test "generates unique tokens" do
      token1 = ApiKeyStorage.generate_token(16)
      token2 = ApiKeyStorage.generate_token(16)
      assert token1 != token2
    end

    test "defaults to 32 bytes" do
      token = ApiKeyStorage.generate_token()
      # 32 bytes -> ~43 base64 characters (no padding)
      assert String.length(token) >= 40
    end
  end

  describe "hash_key/1 and verify_key/2" do
    test "hashes API key with Argon2id" do
      {:ok, hash} = ApiKeyStorage.hash_key("my-api-key")
      assert String.starts_with?(hash, "$argon2id$")
    end

    test "verifies correct API key" do
      api_key = "correct-api-key"
      {:ok, hash} = ApiKeyStorage.hash_key(api_key)

      assert :ok = ApiKeyStorage.verify_key(api_key, hash)
    end

    test "rejects incorrect API key" do
      api_key = "correct-key"
      {:ok, hash} = ApiKeyStorage.hash_key(api_key)

      assert {:error, _} = ApiKeyStorage.verify_key("wrong-key", hash)
    end

    test "different hashes for same key (different salts)" do
      api_key = "same-key"
      {:ok, hash1} = ApiKeyStorage.hash_key(api_key)
      {:ok, hash2} = ApiKeyStorage.hash_key(api_key)

      assert hash1 != hash2  # Different salts
      assert :ok = ApiKeyStorage.verify_key(api_key, hash1)
      assert :ok = ApiKeyStorage.verify_key(api_key, hash2)
    end
  end

  describe "store_key/3 and retrieve_key/3" do
    test "stores and retrieves API key", %{storage_path: storage_path} do
      master_key = ApiKeyStorage.generate_master_key()
      api_key = "my-secret-api-key"

      {:ok, key_id} = ApiKeyStorage.store_key(
        api_key,
        master_key,
        service: "github",
        storage_path: storage_path
      )

      {:ok, retrieved} = ApiKeyStorage.retrieve_key(key_id, master_key, storage_path: storage_path)

      assert retrieved == api_key
    end

    test "stores multiple API keys", %{storage_path: storage_path} do
      master_key = ApiKeyStorage.generate_master_key()

      {:ok, key_id1} = ApiKeyStorage.store_key(
        "github-key",
        master_key,
        service: "github",
        storage_path: storage_path
      )

      {:ok, key_id2} = ApiKeyStorage.store_key(
        "gitlab-key",
        master_key,
        service: "gitlab",
        storage_path: storage_path
      )

      assert key_id1 != key_id2

      {:ok, retrieved1} = ApiKeyStorage.retrieve_key(key_id1, master_key, storage_path: storage_path)
      {:ok, retrieved2} = ApiKeyStorage.retrieve_key(key_id2, master_key, storage_path: storage_path)

      assert retrieved1 == "github-key"
      assert retrieved2 == "gitlab-key"
    end

    test "fails to retrieve with wrong master key", %{storage_path: storage_path} do
      correct_key = ApiKeyStorage.generate_master_key()
      wrong_key = ApiKeyStorage.generate_master_key()

      {:ok, key_id} = ApiKeyStorage.store_key(
        "secret",
        correct_key,
        storage_path: storage_path
      )

      assert {:error, _} = ApiKeyStorage.retrieve_key(key_id, wrong_key, storage_path: storage_path)
    end

    test "fails to retrieve non-existent key", %{storage_path: storage_path} do
      master_key = ApiKeyStorage.generate_master_key()

      assert {:error, "API key not found"} = ApiKeyStorage.retrieve_key(
        "nonexistent-id",
        master_key,
        storage_path: storage_path
      )
    end
  end

  describe "expiration handling" do
    test "stores key with expiration date", %{storage_path: storage_path} do
      master_key = ApiKeyStorage.generate_master_key()
      expires_at = DateTime.utc_now() |> DateTime.add(3600, :second)

      {:ok, key_id} = ApiKeyStorage.store_key(
        "expiring-key",
        master_key,
        expires_at: expires_at,
        storage_path: storage_path
      )

      {:ok, retrieved} = ApiKeyStorage.retrieve_key(key_id, master_key, storage_path: storage_path)
      assert retrieved == "expiring-key"
    end

    test "rejects expired key", %{storage_path: storage_path} do
      master_key = ApiKeyStorage.generate_master_key()
      # Expire 1 hour ago
      expires_at = DateTime.utc_now() |> DateTime.add(-3600, :second)

      {:ok, key_id} = ApiKeyStorage.store_key(
        "expired-key",
        master_key,
        expires_at: expires_at,
        storage_path: storage_path
      )

      assert {:error, "API key has expired"} = ApiKeyStorage.retrieve_key(
        key_id,
        master_key,
        storage_path: storage_path
      )
    end

    test "allows keys without expiration", %{storage_path: storage_path} do
      master_key = ApiKeyStorage.generate_master_key()

      {:ok, key_id} = ApiKeyStorage.store_key(
        "no-expiry",
        master_key,
        storage_path: storage_path
      )

      {:ok, retrieved} = ApiKeyStorage.retrieve_key(key_id, master_key, storage_path: storage_path)
      assert retrieved == "no-expiry"
    end
  end

  describe "delete_key/2" do
    test "deletes API key", %{storage_path: storage_path} do
      master_key = ApiKeyStorage.generate_master_key()

      {:ok, key_id} = ApiKeyStorage.store_key(
        "to-delete",
        master_key,
        storage_path: storage_path
      )

      assert :ok = ApiKeyStorage.delete_key(key_id, storage_path: storage_path)

      assert {:error, "API key not found"} = ApiKeyStorage.retrieve_key(
        key_id,
        master_key,
        storage_path: storage_path
      )
    end

    test "deleting non-existent key succeeds", %{storage_path: storage_path} do
      assert :ok = ApiKeyStorage.delete_key("nonexistent", storage_path: storage_path)
    end

    test "deleting does not affect other keys", %{storage_path: storage_path} do
      master_key = ApiKeyStorage.generate_master_key()

      {:ok, key_id1} = ApiKeyStorage.store_key("key1", master_key, storage_path: storage_path)
      {:ok, key_id2} = ApiKeyStorage.store_key("key2", master_key, storage_path: storage_path)

      assert :ok = ApiKeyStorage.delete_key(key_id1, storage_path: storage_path)

      assert {:error, _} = ApiKeyStorage.retrieve_key(key_id1, master_key, storage_path: storage_path)
      assert {:ok, "key2"} = ApiKeyStorage.retrieve_key(key_id2, master_key, storage_path: storage_path)
    end
  end

  describe "list_keys/1" do
    test "lists all stored keys metadata", %{storage_path: storage_path} do
      master_key = ApiKeyStorage.generate_master_key()

      {:ok, _} = ApiKeyStorage.store_key(
        "github-key",
        master_key,
        service: "github",
        storage_path: storage_path
      )

      {:ok, _} = ApiKeyStorage.store_key(
        "gitlab-key",
        master_key,
        service: "gitlab",
        storage_path: storage_path
      )

      keys = ApiKeyStorage.list_keys(storage_path: storage_path)

      assert length(keys) == 2
      assert Enum.any?(keys, fn k -> k.service == "github" end)
      assert Enum.any?(keys, fn k -> k.service == "gitlab" end)

      # Ensure metadata fields present
      Enum.each(keys, fn key ->
        assert key.key_id != nil
        assert key.service != nil
        assert key.created_at != nil
        assert is_boolean(key.expired?)
      end)
    end

    test "returns empty list for no keys", %{storage_path: storage_path} do
      keys = ApiKeyStorage.list_keys(storage_path: storage_path)
      assert keys == []
    end

    test "marks expired keys", %{storage_path: storage_path} do
      master_key = ApiKeyStorage.generate_master_key()
      expires_at = DateTime.utc_now() |> DateTime.add(-3600, :second)

      {:ok, _} = ApiKeyStorage.store_key(
        "expired",
        master_key,
        expires_at: expires_at,
        storage_path: storage_path
      )

      keys = ApiKeyStorage.list_keys(storage_path: storage_path)
      assert length(keys) == 1
      assert Enum.at(keys, 0).expired? == true
    end
  end

  describe "security properties" do
    test "encrypted keys cannot be read without master key", %{storage_path: storage_path} do
      master_key = ApiKeyStorage.generate_master_key()
      api_key = "super-secret-key"

      {:ok, _key_id} = ApiKeyStorage.store_key(
        api_key,
        master_key,
        storage_path: storage_path
      )

      # Read raw storage file
      {:ok, content} = File.read(storage_path)
      refute String.contains?(content, api_key)  # Plaintext not exposed
    end

    test "storage file has restrictive permissions", %{storage_path: storage_path} do
      master_key = ApiKeyStorage.generate_master_key()

      {:ok, _} = ApiKeyStorage.store_key(
        "test-key",
        master_key,
        storage_path: storage_path
      )

      # Check file permissions (0600 = owner read/write only)
      stat = File.stat!(storage_path)
      mode = stat.mode

      # Extract permission bits (last 9 bits)
      perms = Bitwise.band(mode, 0o777)
      assert perms == 0o600
    end

    test "service context isolation (different encryption contexts)", %{storage_path: storage_path} do
      master_key = ApiKeyStorage.generate_master_key()

      {:ok, key_id1} = ApiKeyStorage.store_key(
        "same-key",
        master_key,
        service: "service1",
        storage_path: storage_path
      )

      {:ok, key_id2} = ApiKeyStorage.store_key(
        "same-key",
        master_key,
        service: "service2",
        storage_path: storage_path
      )

      # Read raw storage
      {:ok, content} = File.read(storage_path)
      {:ok, data} = Jason.decode(content)

      # Find the two stored keys
      stored1 = Enum.find(data, fn k -> k["key_id"] == key_id1 end)
      stored2 = Enum.find(data, fn k -> k["key_id"] == key_id2 end)

      # Different encryption contexts mean different ciphertexts
      assert stored1["encrypted_key"] != stored2["encrypted_key"]
    end
  end
end
