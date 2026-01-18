// SPDX-License-Identifier: PMPL-1.0

import { postJson } from "../http.ts";
import type { HttpOptions } from "../types.ts";

/** Attest a package path with claim-forge service */
export async function attest(
  path: string,
  baseUrl: string,
  token: string | undefined,
  opts: HttpOptions,
): Promise<void> {
  const body = JSON.stringify({ path });
  await postJson(baseUrl, "/attest", token, body, opts);
}
