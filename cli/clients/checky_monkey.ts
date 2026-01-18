// SPDX-License-Identifier: PMPL-1.0

import { postJson } from "../http.ts";
import type { HttpOptions } from "../types.ts";

/** Analyze a package path with checky-monkey service */
export async function analyze(
  path: string,
  baseUrl: string,
  token: string | undefined,
  opts: HttpOptions,
): Promise<void> {
  const body = JSON.stringify({ path });
  await postJson(baseUrl, "/analyze", token, body, opts);
}
