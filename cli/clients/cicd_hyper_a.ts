// SPDX-License-Identifier: PMPL-1.0

import { postJson } from "../http.ts";
import type { HttpOptions } from "../types.ts";

/** Publish a package to cicd-hyper-a registry */
export async function publish(
  path: string,
  baseUrl: string,
  token: string | undefined,
  opts: HttpOptions,
): Promise<void> {
  const body = JSON.stringify({ path });
  await postJson(baseUrl, "/publish", token, body, opts);
}
