// SPDX-License-Identifier: PMPL-1.0

import { postJson } from "../http.ts";
import type { HttpOptions } from "../types.ts";

/** Audit licenses for a package path with palimpsest-license service */
export async function audit(
  path: string,
  baseUrl: string,
  token: string | undefined,
  opts: HttpOptions,
): Promise<void> {
  const body = JSON.stringify({ path });
  await postJson(baseUrl, "/audit", token, body, opts);
}
