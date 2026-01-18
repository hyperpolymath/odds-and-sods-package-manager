// SPDX-License-Identifier: PMPL-1.0

import { parse as parseToml } from "@std/toml";
import { join } from "@std/path";
import { SafeUrl } from "@proven/mod.ts";
import type { HttpConfig, OpmConfig, ServiceConfig } from "./types.ts";

const DEFAULT_HTTP_CONFIG: HttpConfig = {
  timeoutMs: 3000,
  retries: 2,
  backoffMs: 200,
};

function defaultServiceConfig(port: number): ServiceConfig {
  return {
    baseUrl: `http://127.0.0.1:${port}`,
    token: undefined,
  };
}

/** Returns example/default configuration */
export function exampleConfig(): OpmConfig {
  return {
    http: DEFAULT_HTTP_CONFIG,
    claimForge: defaultServiceConfig(7001),
    checkyMonkey: defaultServiceConfig(7002),
    palimpsestLicense: defaultServiceConfig(7003),
    cicdHyperA: defaultServiceConfig(7004),
    oikos: defaultServiceConfig(7005),
  };
}

/**
 * Validate a service URL using proven's SafeUrl.
 * Returns the URL if valid, throws if invalid.
 */
function validateServiceUrl(url: string, serviceName: string): string {
  const result = SafeUrl.parse(url);
  if (!result.ok) {
    throw new Error(`Invalid URL for ${serviceName}: ${url}`);
  }
  return url;
}

/** Load config from a specific file path */
export async function loadConfigFrom(path: string): Promise<OpmConfig> {
  const data = await Deno.readTextFile(path);
  const raw = parseToml(data) as Record<string, unknown>;

  const httpRaw = (raw.http ?? {}) as Record<string, unknown>;
  const http: HttpConfig = {
    timeoutMs: (httpRaw.timeout_ms as number) ?? DEFAULT_HTTP_CONFIG.timeoutMs,
    retries: (httpRaw.retries as number) ?? DEFAULT_HTTP_CONFIG.retries,
    backoffMs: (httpRaw.backoff_ms as number) ?? DEFAULT_HTTP_CONFIG.backoffMs,
  };

  function parseService(key: string, defaultPort: number): ServiceConfig {
    const svc = (raw[key] ?? {}) as Record<string, unknown>;
    const rawUrl = (svc.base_url as string) ?? `http://127.0.0.1:${defaultPort}`;
    return {
      baseUrl: validateServiceUrl(rawUrl, key),
      token: svc.token as string | undefined,
    };
  }

  return {
    http,
    claimForge: parseService("claim_forge", 7001),
    checkyMonkey: parseService("checky_monkey", 7002),
    palimpsestLicense: parseService("palimpsest_license", 7003),
    cicdHyperA: parseService("cicd_hyper_a", 7004),
    oikos: parseService("oikos", 7005),
  };
}

/** Check if a file exists */
async function fileExists(path: string): Promise<boolean> {
  try {
    await Deno.stat(path);
    return true;
  } catch {
    return false;
  }
}

/**
 * Load configuration using search order:
 * 1. $OPM_CONFIG environment variable
 * 2. ./opm.toml (local directory)
 * 3. ~/.config/opm/opm.toml (user config)
 */
export async function loadConfig(): Promise<OpmConfig> {
  const envPath = Deno.env.get("OPM_CONFIG");
  if (envPath) {
    return await loadConfigFrom(envPath);
  }

  const localPath = "opm.toml";
  if (await fileExists(localPath)) {
    return await loadConfigFrom(localPath);
  }

  const home = Deno.env.get("HOME");
  if (home) {
    const userPath = join(home, ".config", "opm", "opm.toml");
    if (await fileExists(userPath)) {
      return await loadConfigFrom(userPath);
    }
  }

  throw new Error("opm config not found");
}

/** Load config with fallback to example config */
export async function loadConfigOrExample(): Promise<OpmConfig> {
  try {
    return await loadConfig();
  } catch {
    return exampleConfig();
  }
}
