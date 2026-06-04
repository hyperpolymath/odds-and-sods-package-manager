# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Storage.Backend do
  @moduledoc """
  Behaviour for OPSM tarball storage backends.

  Each backend implements four operations: put (upload), get (fetch to path),
  exists? (cheap presence check), and url (public retrieval URL if available).

  Backends must be non-blocking and return error tuples on failure — the caller
  (StorageManager) decides whether to fall through to the next backend.
  """

  @doc "Upload a local file to the backend. Returns {:ok, key} or {:error, reason}."
  @callback put(key :: String.t(), local_path :: Path.t(), opts :: keyword()) ::
              {:ok, String.t()} | {:error, term()}

  @doc "Fetch from the backend to a local path. Returns {:ok, local_path} or {:error, reason}."
  @callback get(key :: String.t(), dest_path :: Path.t(), opts :: keyword()) ::
              {:ok, Path.t()} | {:error, term()}

  @doc "Return true if the backend has the key. Errors are treated as false."
  @callback exists?(key :: String.t(), opts :: keyword()) :: boolean()

  @doc "Return a retrieval URL if the backend supports public access, else nil."
  @callback url(key :: String.t(), opts :: keyword()) :: String.t() | nil
end
