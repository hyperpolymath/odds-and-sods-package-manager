# SPDX-License-Identifier: MPL-2.0

defmodule Opsm.Crypto.ApiKeyStorage do
  @moduledoc """
  Secure API key storage with encryption and hashing.

  Features:
  - ChaCha20-Poly1305 encryption for API key storage (256-bit keys)
  - Argon2id hashing for API key verification (512 MiB, 8 iter, 4 lanes)
  - ChaCha20-DRBG for secure token generation (512-bit seed)
  - Prevents plaintext API key exposure in configuration files

  Use Cases:
  - Trust service authentication tokens
  - Registry API keys
  - User credentials for web dashboard
  - Session tokens for CLI

  Aligns with SECURITY-STANDARDS.scm requirements for API key storage.

  ## Storage Format

  Encrypted API keys are stored as:
  ```elixir
  %{
    "encrypted_key" => base64_encoded_encrypted_data,
    "key_id" => unique_identifier,
    "service" => "trust-service-name",
    "created_at" => iso8601_timestamp,
    "expires_at" => iso8601_timestamp | nil
  }
  ```

  ## Examples

      # Generate a secure master key (store this safely!)
      master_key = Opsm.Crypto.ApiKeyStorage.generate_master_key()

      # Store an API key (encrypted)
      {:ok, key_id} = Opsm.Crypto.ApiKeyStorage.store_key(
        "my-api-key-secret",
        master_key,
        service: "github",
        expires_at: ~U[2027-01-01 00:00:00Z]
      )

      # Retrieve an API key (decrypted)
      {:ok, "my-api-key-secret"} = Opsm.Crypto.ApiKeyStorage.retrieve_key(
        key_id,
        master_key
      )

      # Verify an API key (using Argon2id)
      {:ok, hash} = Opsm.Crypto.ApiKeyStorage.hash_key("my-api-key-secret")
      :ok = Opsm.Crypto.ApiKeyStorage.verify_key("my-api-key-secret", hash)

      # Generate a session token
      token = Opsm.Crypto.ApiKeyStorage.generate_token(32)
  """

  alias Opsm.Crypto.{Password, Symmetric, RNG}

  @type key_id :: String.t()
  @type master_key :: binary()
  @type api_key :: String.t()

  @type stored_key :: %{
    encrypted_key: binary(),
    key_id: key_id(),
    service: String.t(),
    created_at: DateTime.t(),
    expires_at: DateTime.t() | nil
  }

  @doc """
  Generate a 256-bit master key for encrypting API keys.

  Store this key securely (e.g., environment variable, secrets manager).
  Never commit master keys to version control!

  ## Examples

      iex> master_key = Opsm.Crypto.ApiKeyStorage.generate_master_key()
      iex> byte_size(master_key)
      32
  """
  def generate_master_key do
    RNG.generate_key_256bit()
  end

  @doc """
  Generate a cryptographically secure session token.

  Uses ChaCha20-DRBG for high-entropy token generation.

  ## Examples

      iex> token = Opsm.Crypto.ApiKeyStorage.generate_token(32)
      iex> byte_size(token)
      32

      iex> token1 = Opsm.Crypto.ApiKeyStorage.generate_token(16)
      iex> token2 = Opsm.Crypto.ApiKeyStorage.generate_token(16)
      iex> token1 != token2
      true
  """
  def generate_token(byte_length \\ 32) when is_integer(byte_length) and byte_length > 0 do
    RNG.generate_bytes(byte_length)
    |> Base.url_encode64(padding: false)
  end

  @doc """
  Hash an API key using Argon2id for verification purposes.

  Use this when you need to verify an API key without storing it in plaintext.
  For encrypted storage, use `store_key/3` instead.

  ## Examples

      iex> {:ok, hash} = Opsm.Crypto.ApiKeyStorage.hash_key("secret-api-key")
      iex> String.starts_with?(hash, "$argon2id$")
      true
  """
  def hash_key(api_key) when is_binary(api_key) do
    Password.hash(api_key)
  end

  @doc """
  Verify an API key against its Argon2id hash.

  ## Examples

      iex> {:ok, hash} = Opsm.Crypto.ApiKeyStorage.hash_key("correct-key")
      iex> Opsm.Crypto.ApiKeyStorage.verify_key("correct-key", hash)
      :ok
      iex> Opsm.Crypto.ApiKeyStorage.verify_key("wrong-key", hash)
      {:error, "Password verification failed"}
  """
  def verify_key(api_key, hash) when is_binary(api_key) and is_binary(hash) do
    Password.verify(api_key, hash)
  end

  @doc """
  Store an API key encrypted with ChaCha20-Poly1305.

  Returns {:ok, key_id} where key_id is a unique identifier for retrieval.

  Options:
  - service: Service name (e.g., "github", "trust-service")
  - expires_at: DateTime when the key expires (nil for no expiration)
  - storage_path: Path to store encrypted keys (default: "~/.opsm/api_keys.json")

  ## Examples

      iex> master_key = Opsm.Crypto.ApiKeyStorage.generate_master_key()
      iex> {:ok, key_id} = Opsm.Crypto.ApiKeyStorage.store_key(
      ...>   "my-secret-key",
      ...>   master_key,
      ...>   service: "github"
      ...> )
      iex> is_binary(key_id)
      true
  """
  def store_key(api_key, master_key, opts \\ []) do
    service = Keyword.get(opts, :service, "unknown")
    expires_at = Keyword.get(opts, :expires_at)
    storage_path = Keyword.get(opts, :storage_path, default_storage_path())

    # Generate unique key ID
    key_id = generate_token(16)

    # Encrypt the API key
    context = "opsm-api-key-#{service}"
    case Symmetric.encrypt(api_key, master_key, context) do
      {:ok, encrypted} ->
        stored_key = %{
          "encrypted_key" => Base.encode64(encrypted),
          "key_id" => key_id,
          "service" => service,
          "created_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
          "expires_at" => expires_at && DateTime.to_iso8601(expires_at)
        }

        # Save to storage
        case save_to_storage(stored_key, storage_path) do
          :ok -> {:ok, key_id}
          {:error, reason} -> {:error, "Failed to store key: #{reason}"}
        end

      {:error, reason} ->
        {:error, "Failed to encrypt key: #{reason}"}
    end
  end

  @doc """
  Retrieve and decrypt an API key by its key_id.

  Returns {:ok, api_key} or {:error, reason}.

  Options:
  - storage_path: Path to encrypted keys storage (default: "~/.opsm/api_keys.json")

  ## Examples

      iex> master_key = Opsm.Crypto.ApiKeyStorage.generate_master_key()
      iex> {:ok, key_id} = Opsm.Crypto.ApiKeyStorage.store_key("secret", master_key)
      iex> {:ok, "secret"} = Opsm.Crypto.ApiKeyStorage.retrieve_key(key_id, master_key)
  """
  def retrieve_key(key_id, master_key, opts \\ []) do
    storage_path = Keyword.get(opts, :storage_path, default_storage_path())

    with {:ok, stored_key} <- load_from_storage(key_id, storage_path),
         :ok <- check_expiration(stored_key),
         {:ok, encrypted} <- Base.decode64(stored_key["encrypted_key"]),
         context = "opsm-api-key-#{stored_key["service"]}",
         {:ok, decrypted} <- Symmetric.decrypt(encrypted, master_key, context) do
      {:ok, decrypted}
    else
      {:error, :expired} -> {:error, "API key has expired"}
      {:error, :not_found} -> {:error, "API key not found"}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Delete an API key from storage.

  ## Examples

      iex> master_key = Opsm.Crypto.ApiKeyStorage.generate_master_key()
      iex> {:ok, key_id} = Opsm.Crypto.ApiKeyStorage.store_key("secret", master_key)
      iex> :ok = Opsm.Crypto.ApiKeyStorage.delete_key(key_id)
      iex> {:error, _} = Opsm.Crypto.ApiKeyStorage.retrieve_key(key_id, master_key)
  """
  def delete_key(key_id, opts \\ []) do
    storage_path = Keyword.get(opts, :storage_path, default_storage_path())

    with {:ok, keys} <- read_storage_file(storage_path) do
      updated_keys = Enum.reject(keys, fn key -> key["key_id"] == key_id end)
      write_storage_file(storage_path, updated_keys)
    else
      {:error, :enoent} -> :ok  # Already deleted
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  List all stored API key metadata (without decrypting keys).

  Returns list of %{key_id, service, created_at, expires_at, expired?}.

  ## Examples

      iex> master_key = Opsm.Crypto.ApiKeyStorage.generate_master_key()
      iex> {:ok, _} = Opsm.Crypto.ApiKeyStorage.store_key("key1", master_key, service: "github")
      iex> {:ok, _} = Opsm.Crypto.ApiKeyStorage.store_key("key2", master_key, service: "gitlab")
      iex> keys = Opsm.Crypto.ApiKeyStorage.list_keys()
      iex> length(keys) >= 2
      true
  """
  def list_keys(opts \\ []) do
    storage_path = Keyword.get(opts, :storage_path, default_storage_path())

    case read_storage_file(storage_path) do
      {:ok, keys} ->
        Enum.map(keys, fn key ->
          %{
            key_id: key["key_id"],
            service: key["service"],
            created_at: key["created_at"],
            expires_at: key["expires_at"],
            expired?: is_expired?(key)
          }
        end)

      {:error, :enoent} ->
        []

      {:error, _reason} ->
        []
    end
  end

  # Private functions

  defp default_storage_path do
    home = System.user_home!()
    Path.join([home, ".opsm", "api_keys.json"])
  end

  defp save_to_storage(stored_key, storage_path) do
    with {:ok, keys} <- read_storage_file(storage_path) do
      updated_keys = [stored_key | keys]
      write_storage_file(storage_path, updated_keys)
    else
      {:error, :enoent} ->
        # First key, create file
        write_storage_file(storage_path, [stored_key])

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp load_from_storage(key_id, storage_path) do
    case read_storage_file(storage_path) do
      {:ok, keys} ->
        case Enum.find(keys, fn key -> key["key_id"] == key_id end) do
          nil -> {:error, :not_found}
          key -> {:ok, key}
        end

      {:error, :enoent} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp read_storage_file(path) do
    case File.read(path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, data} -> {:ok, data}
          {:error, reason} -> {:error, "Invalid JSON: #{inspect(reason)}"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp write_storage_file(path, keys) do
    # Ensure directory exists
    Path.dirname(path) |> File.mkdir_p!()

    # Write with restricted permissions (0600 - owner read/write only)
    json = Jason.encode!(keys, pretty: true)

    case File.write(path, json, [:write]) do
      :ok ->
        # Set restrictive permissions (owner only)
        File.chmod!(path, 0o600)
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp check_expiration(stored_key) do
    case stored_key["expires_at"] do
      nil -> :ok
      expires_at_str ->
        case DateTime.from_iso8601(expires_at_str) do
          {:ok, expires_at, _offset} ->
            if DateTime.compare(DateTime.utc_now(), expires_at) == :lt do
              :ok
            else
              {:error, :expired}
            end

          {:error, _} ->
            {:error, "Invalid expiration date format"}
        end
    end
  end

  defp is_expired?(stored_key) do
    case stored_key["expires_at"] do
      nil -> false
      expires_at_str ->
        case DateTime.from_iso8601(expires_at_str) do
          {:ok, expires_at, _offset} ->
            DateTime.compare(DateTime.utc_now(), expires_at) != :lt

          {:error, _} ->
            false
        end
    end
  end
end
