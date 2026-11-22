#!/usr/bin/env node
// The guard on TRON - script/BittyV1Guard<Chain>.s.sol's counterpart, in Node because forge cannot
// broadcast to TRON (its JSON-RPC accepts no transactions). Reads and writes
// deployments/<network>.json, as the forge scripts do deployments/<chain>.toml.
//
//   node tron/deploy.mjs --network tron-nile --dry-run     what would be sent; no key needed
//   node tron/deploy.mjs --network tron-nile               Nile
//   node tron/deploy.mjs --network tron                    TRON mainnet
//   node tron/deploy.mjs --network tron --rpc <node url>   through another node (e.g. Alchemy's)
//
// Env: TRON_PRIVATE_KEY - the DEPLOYER key (hex). The bootstrap's upgrade and initialize gate on
//      tx.origin == DEPLOYER, so no other key can finish a deploy.
//      TRON_PRO_API_KEY - optional, TronGrid rate limits.
//      TRON_FULL_HOST - optional, same as --rpc: a node URL to use instead of the config's fullHost
//      (e.g. one with a provider key in its path). Never written to deployments/<network>.json, so the
//      key is not committed. The node must serve /wallet/* and /jsonrpc.

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
    rpc: { type: "string" },
  },
});
if (!values.network) {
  console.error("usage: node tron/deploy.mjs --network <tron-nile|tron> [--dry-run] [--rpc <node url>]");
  process.exit(1);
}

const configPath = join(repo, "deployments", `${values.network}.json`);
const config = JSON.parse(readFileSync(configPath, "utf8"));
config.deployed ??= {};
const dryRun = values["dry-run"];
if (!dryRun && !process.env.TRON_PRIVATE_KEY) throw new Error("TRON_PRIVATE_KEY is not set (or pass --dry-run)");

const chain = new Chain({
  fullHost: values.rpc || process.env.TRON_FULL_HOST || config.fullHost,
  privateKey: process.env.TRON_PRIVATE_KEY,
  apiKey: process.env.TRON_PRO_API_KEY,
  feeLimitTrx: config.feeLimitTrx,
  dryRun,
});

console.log(`TRON ${config.network} (chain ${config.chainId})${dryRun ? " - dry run, nothing is sent" : ""}`);

// 0. the DEPLOYER must be a funded TRON account. An address is not an account until it has received
//    TRX, and the node refuses every transaction from one that is not ("account … does not exist").
//    The whole guard deploy uses about 4.6M energy (4,531,379 on Nile, 2026-11-09) and 26 KB of
//    bandwidth; whatever the account does not already have (staked or rented) is burned from its
//    TRX. Checked here, before the build, so an underfunded run stops with the address to fund
//    instead of failing on its first send.
const GUARD_DEPLOY_ENERGY = 5_000_000;
const GUARD_DEPLOY_BANDWIDTH = 30_000; // bytes; each one missing burns 1,000 sun
{
  const deployerBase58 = toBase58(config.DEPLOYER);
  const account = await chain.tronWeb.trx.getAccount(deployerBase58);
  const balanceTrx = (account?.balance ?? 0) / 1_000_000;
  const params = await chain.tronWeb.trx.getChainParameters();
  const energyFeeSun = params.find((p) => p.key === "getEnergyFee")?.value ?? 100;
  const exists = Boolean(account?.address);
  // Energy and bandwidth on hand: staked by the account itself or delegated to it (rented).
  const res = exists ? await chain.tronWeb.trx.getAccountResources(deployerBase58) : {};
  const energy = Math.max(0, (res.EnergyLimit ?? 0) - (res.EnergyUsed ?? 0));
  const bandwidth = Math.max(0, (res.NetLimit ?? 0) - (res.NetUsed ?? 0));
  const energyShort = Math.max(0, GUARD_DEPLOY_ENERGY - energy);
  const bandwidthShort = Math.max(0, GUARD_DEPLOY_BANDWIDTH - bandwidth);
  // At least 10 TRX even when every resource is on hand, for the odd estimate that runs over.
  const neededTrx = Math.max(10, Math.ceil((energyShort * energyFeeSun + bandwidthShort * 1_000) / 1_000_000));
  console.log(`DEPLOYER ${deployerBase58} (${toEvm(config.DEPLOYER)}): ${exists ? `${balanceTrx} TRX` : "no account yet"}`);
  console.log(`  energy ${energy} of ~${GUARD_DEPLOY_ENERGY} on hand, bandwidth ${bandwidth} of ~${GUARD_DEPLOY_BANDWIDTH} bytes`);
  if (!exists || balanceTrx < neededTrx) {
    const message = [
      "",
      `Fund the DEPLOYER on TRON ${config.network} before deploying:`,
      "",
      `    ${deployerBase58}`,
      "",
      `  balance now: ${exists ? `${balanceTrx} TRX` : "none (the account does not exist until it receives TRX)"}`,
      `  needed:      about ${neededTrx} TRX, to burn for the ${energyShort} energy and ${bandwidthShort} bytes of`,
      `               bandwidth not on hand (${energyFeeSun} sun per energy); rent energy first to need less`,
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
