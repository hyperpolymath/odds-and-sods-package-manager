// SPDX-License-Identifier: PMPL-1.0

import { SafeJson, type Result, err, ok } from "@proven/mod.ts";
import type { HttpOptions } from "./types.ts";

export type { Result };

/** Sleep for a given number of milliseconds */
function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/**
 * POST JSON to a service endpoint with retries and exponential backoff.
 */
export async function postJson(
  baseUrl: string,
  path: string,
  token: string | undefined,
  body: string,
  opts: HttpOptions,
): Promise<void> {
  const url = `${baseUrl.replace(/\/+$/, "")}${path}`;
  const attempts = opts.retries + 1;

  const headers: HeadersInit = {
    "Content-Type": "application/json",
  };
  if (token) {
    headers["Authorization"] = `Bearer ${token}`;
  }

  let lastError: Error | null = null;

  for (let attempt = 0; attempt < attempts; attempt++) {
    try {
      const controller = new AbortController();
      const timeoutId = setTimeout(() => controller.abort(), opts.timeoutMs);

      const response = await fetch(url, {
        method: "POST",
        headers,
        body,
        signal: controller.signal,
      });

      clearTimeout(timeoutId);

      if (response.ok) {
        return;
      }

      lastError = new Error(`HTTP error: ${response.status} ${response.statusText}`);

      if (attempt + 1 < attempts) {
        await sleep(opts.backoffMs * (attempt + 1));
      }
    } catch (err) {
      lastError = err instanceof Error ? err : new Error(String(err));

      if (attempt + 1 < attempts) {
        await sleep(opts.backoffMs * (attempt + 1));
      }
    }
  }

  throw lastError ?? new Error("Request failed");
}

/**
 * GET JSON from a service endpoint with retries and exponential backoff.
 * Uses proven's SafeJson for safe parsing.
 */
export async function getJson<T>(
  baseUrl: string,
  path: string,
  token: string | undefined,
  opts: HttpOptions,
): Promise<Result<T>> {
  const url = `${baseUrl.replace(/\/+$/, "")}${path}`;
  const attempts = opts.retries + 1;

  const headers: HeadersInit = {
    "Accept": "application/json",
  };
  if (token) {
    headers["Authorization"] = `Bearer ${token}`;
  }

  let lastError = "Request failed";

  for (let attempt = 0; attempt < attempts; attempt++) {
    try {
      const controller = new AbortController();
      const timeoutId = setTimeout(() => controller.abort(), opts.timeoutMs);

      const response = await fetch(url, {
        method: "GET",
        headers,
        signal: controller.signal,
      });

      clearTimeout(timeoutId);

      if (response.ok) {
        const text = await response.text();
        const parsed = SafeJson.parse(text);
        if (parsed.ok) {
          return ok(parsed.value as T);
        }
        return err(`JSON parse error: ${parsed.error}`);
      }

      lastError = `HTTP error: ${response.status} ${response.statusText}`;

      if (attempt + 1 < attempts) {
        await sleep(opts.backoffMs * (attempt + 1));
      }
    } catch (e) {
      lastError = e instanceof Error ? e.message : String(e);

      if (attempt + 1 < attempts) {
        await sleep(opts.backoffMs * (attempt + 1));
      }
    }
  }

  return err(lastError);
}
