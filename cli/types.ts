// SPDX-License-Identifier: PMPL-1.0

/** HTTP client configuration */
export interface HttpConfig {
  timeoutMs: number;
  retries: number;
  backoffMs: number;
}

/** Service endpoint configuration */
export interface ServiceConfig {
  baseUrl: string;
  token?: string;
}

/** Full OPM configuration */
export interface OpmConfig {
  http: HttpConfig;
  claimForge: ServiceConfig;
  checkyMonkey: ServiceConfig;
  palimpsestLicense: ServiceConfig;
  cicdHyperA: ServiceConfig;
  oikos: ServiceConfig;
}

/** HTTP request options */
export interface HttpOptions {
  timeoutMs: number;
  retries: number;
  backoffMs: number;
}

/** Publish request payload */
export interface PublishRequest {
  path: string;
}

/** Audit request payload */
export interface AuditRequest {
  package: string;
}

/** Status response from registry */
export interface StatusResponse {
  registryHub: string;
  federation: string;
}
