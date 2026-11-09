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

// 0. the DEPLOYER must be a funded TRON account. An address is not an account until it has received
//    TRX, and the node refuses every transaction from one that is not ("account … does not exist").
//    The whole guard deploy burns about 5M energy when none is staked; checked here, before the build,
//    so an unfunded run stops with the address to fund instead of failing on its first send.
const GUARD_DEPLOY_ENERGY = 5_000_000;
const BANDWIDTH_TRX = 30;
{
  const deployerBase58 = toBase58(config.DEPLOYER);
  const account = await chain.tronWeb.trx.getAccount(deployerBase58);
  const balanceTrx = (account?.balance ?? 0) / 1_000_000;
  const params = await chain.tronWeb.trx.getChainParameters();
  const energyFeeSun = params.find((p) => p.key === "getEnergyFee")?.value ?? 100;
  const neededTrx = Math.ceil((GUARD_DEPLOY_ENERGY * energyFeeSun) / 1_000_000 + BANDWIDTH_TRX);
  const exists = Boolean(account?.address);
  console.log(`DEPLOYER ${deployerBase58} (${toEvm(config.DEPLOYER)}): ${exists ? `${balanceTrx} TRX` : "no account yet"}`);
  if (!exists || balanceTrx < neededTrx) {
    const message = [
      "",
      `Fund the DEPLOYER on TRON ${config.network} before deploying:`,
      "",
      `    ${deployerBase58}`,
      "",
      `  balance now: ${exists ? `${balanceTrx} TRX` : "none (the account does not exist until it receives TRX)"}`,
      `  needed:      about ${neededTrx} TRX (${GUARD_DEPLOY_ENERGY / 1e6}M energy at ${energyFeeSun} sun, plus bandwidth),`,
      "               less if the account has staked energy",
      ...(config.network === "nile" ? ["  Nile test TRX: https://nileex.io/join/getJoinPage"] : []),
      "",
    ].join("\n");
    if (!dryRun) {
      console.error(message);
      process.exit(1);
    }
    console.log(message + "  [dry-run] continuing anyway, to show what would be sent\n");
  }
}

forgeBuild(repo);

// 1. the CREATE2 deployer every Bitty contract on this network is placed through
const deployer = await deployCreate2Deployer({ chain, repo, config, build: false });
if (!deployer) {
  console.log("  [dry-run] every guard address depends on where the CREATE2 deployer lands, so the plan stops here");
  process.exit(0);
}
// Saved now, not with the rest at the end: every guard address hangs off this one, so if a later step
// fails, a re-run must reuse it - a second deployer would move every address and strand what is
// already deployed.
if (!dryRun && config.deployed.CREATE2_DEPLOYER?.evm !== toEvm(deployer)) {
  config.deployed.CREATE2_DEPLOYER = { evm: toEvm(deployer), base58: toBase58(deployer) };
  writeFileSync(configPath, JSON.stringify(config, null, 2) + "\n");
  console.log(`CREATE2 deployer recorded in deployments/${values.network}.json`);
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
