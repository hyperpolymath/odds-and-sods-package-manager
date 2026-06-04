# SPDX-License-Identifier: MPL-2.0
# Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
defmodule Opsm.Types.ContainerImage do
  @moduledoc """
  Container image metadata.
  """

  @type t :: %__MODULE__{
          tag: String.t(),
          digest: String.t() | nil,
          runtime: String.t(),
          size: integer() | nil,
          created_at: String.t() | nil
        }

  defstruct [:tag, :digest, :runtime, :size, :created_at]
end

defmodule Opsm.Types.ScanResult do
  @moduledoc """
  Vulnerability scan result from Svalinn.
  """

  @type t :: %__MODULE__{
          critical: integer(),
          high: integer(),
          medium: integer(),
          low: integer(),
          total: integer(),
          findings: list(map())
        }

  defstruct critical: 0,
            high: 0,
            medium: 0,
            low: 0,
            total: 0,
            findings: []
end

defmodule Opsm.Types.SignatureResult do
  @moduledoc """
  Image signature result from Selur.
  """

  @type t :: %__MODULE__{
          signature: String.t(),
          algorithm: String.t(),
          signed_at: String.t() | nil,
          key_id: String.t() | nil
        }

  defstruct [:signature, :algorithm, :signed_at, :key_id]
end

defmodule Opsm.Types.OciImage do
  @moduledoc """
  OCI image specification.

  Represents a standardized container image with:
  - Manifest (image metadata)
  - Config (runtime configuration)
  - Layers (filesystem layers)
  - Signatures (cryptographic verification)
  """

  @type t :: %__MODULE__{
          registry: String.t(),
          repository: String.t(),
          tag: String.t(),
          digest: String.t() | nil,
          manifest: map(),
          config: map(),
          layers: list(String.t()),
          signatures: list(SignatureResult.t()),
          attestations: list(map())
        }

  defstruct [
    :registry,
    :repository,
    :tag,
    :digest,
    :manifest,
    :config,
    layers: [],
    signatures: [],
    attestations: []
  ]
end
