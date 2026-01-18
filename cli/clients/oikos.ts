// SPDX-License-Identifier: PMPL-1.0

import { postJson } from "../http.ts";
import type { HttpOptions } from "../types.ts";

/** Score a package for sustainability with oikos service */
export async function score(
  packageName: string,
  baseUrl: string,
  token: string | undefined,
  opts: HttpOptions,
): Promise<void> {
  const body = JSON.stringify({ package: packageName });
  await postJson(baseUrl, "/score", token, body, opts);
}
