#!/usr/bin/env node
// The guard on TRON - script/BittyV1Guard<Chain>.s.sol's counterpart, in Node because forge cannot
// broadcast to TRON (its JSON-RPC accepts no transactions). Reads and writes
// deployments/<network>.json, as the forge scripts do deployments/<chain>.toml.
//
//   node tron/deploy.mjs --network tron-nile --dry-run     what would be sent; no key needed
//   node tron/deploy.mjs --network tron-nile               Nile
//   node tron/deploy.mjs --network tron                    TRON mainnet
//
// Env: TRON_PRIVATE_KEY - the DEPLOYER key (hex). The bootstrap's upgrade and initialize gate on
//      tx.origin == DEPLOYER, so no other key can finish a deploy.
//      TRON_PRO_API_KEY - optional, TronGrid rate limits.

import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";
import { toBase58, toEvm } from "./lib/address.mjs";
import { Chain } from "./lib/chain.mjs";
import { deployCreate2Deployer, deployGuard, forgeBuild, outputs, planGuard } from "./lib/guard.mjs";

const repo = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const { values } = parseArgs({
  options: {
    network: { type: "string" },
    "dry-run": { type: "boolean", default: false },
  },
});
if (!values.network) {
  console.error("usage: node tron/deploy.mjs --network <tron-nile|tron> [--dry-run]");
  process.exit(1);
}

const configPath = join(repo, "deployments", `${values.network}.json`);
const config = JSON.parse(readFileSync(configPath, "utf8"));
config.deployed ??= {};
const dryRun = values["dry-run"];
if (!dryRun && !process.env.TRON_PRIVATE_KEY) throw new Error("TRON_PRIVATE_KEY is not set (or pass --dry-run)");

const chain = new Chain({
  fullHost: config.fullHost,
  privateKey: process.env.TRON_PRIVATE_KEY,
  apiKey: process.env.TRON_PRO_API_KEY,
  feeLimitTrx: config.feeLimitTrx,
  dryRun,
});

console.log(`TRON ${config.network} (chain ${config.chainId})${dryRun ? " - dry run, nothing is sent" : ""}`);
forgeBuild(repo);

// 1. the CREATE2 deployer every Bitty contract on this network is placed through
const deployer = await deployCreate2Deployer({ chain, repo, config, build: false });
if (!deployer) {
  console.log("  [dry-run] every guard address depends on where the CREATE2 deployer lands, so the plan stops here");
  process.exit(0);
}

// 2. the guard
const plan = planGuard({ repo, deployer, build: false });
await deployGuard({ chain, plan, config });

const out = outputs(plan);
console.table(Object.fromEntries(Object.entries(out).map(([k, v]) => [k, v.base58])));
if (!dryRun) {
  config.deployed = { ...config.deployed, ...out };
  writeFileSync(configPath, JSON.stringify(config, null, 2) + "\n");
  console.log(`addresses written to deployments/${values.network}.json`);
  console.log(`guard: ${config.explorer}/#/contract/${toBase58(out.BITTY_GUARD.evm)}`);
}
