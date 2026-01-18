// SPDX-License-Identifier: PMPL-1.0

import { loadConfigOrExample } from "./config.ts";
import type { HttpOptions } from "./types.ts";
import * as claimForge from "./clients/claim_forge.ts";
import * as checkyMonkey from "./clients/checky_monkey.ts";
import * as palimpsestLicense from "./clients/palimpsest_license.ts";
import * as cicdHyperA from "./clients/cicd_hyper_a.ts";
import * as oikos from "./clients/oikos.ts";

/** Publish a package through the trust pipeline */
export async function publish(path: string): Promise<void> {
  console.log(`opm publish (stub) for ${path}`);

  const cfg = await loadConfigOrExample();
  const opts: HttpOptions = {
    timeoutMs: cfg.http.timeoutMs,
    retries: cfg.http.retries,
    backoffMs: cfg.http.backoffMs,
  };

  await claimForge.attest(path, cfg.claimForge.baseUrl, cfg.claimForge.token, opts);
  await checkyMonkey.analyze(path, cfg.checkyMonkey.baseUrl, cfg.checkyMonkey.token, opts);
  await palimpsestLicense.audit(
    path,
    cfg.palimpsestLicense.baseUrl,
    cfg.palimpsestLicense.token,
    opts,
  );
  await cicdHyperA.publish(path, cfg.cicdHyperA.baseUrl, cfg.cicdHyperA.token, opts);
}

/** Audit a package through the trust pipeline */
export async function audit(packageName: string): Promise<void> {
  console.log(`opm audit (stub) for ${packageName}`);

  const cfg = await loadConfigOrExample();
  const opts: HttpOptions = {
    timeoutMs: cfg.http.timeoutMs,
    retries: cfg.http.retries,
    backoffMs: cfg.http.backoffMs,
  };

  await claimForge.attest(packageName, cfg.claimForge.baseUrl, cfg.claimForge.token, opts);
  await checkyMonkey.analyze(packageName, cfg.checkyMonkey.baseUrl, cfg.checkyMonkey.token, opts);
  await oikos.score(packageName, cfg.oikos.baseUrl, cfg.oikos.token, opts);
}

/** Show federation and registry status */
export function status(): void {
  console.log("opm status (stub)");
  console.log("- federation: git-private-farm + Radicle + IPFS");
  console.log("- registry: opm-registry-hub");
}
