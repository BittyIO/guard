// The guard on TRON: where each piece lands, and the sends that put it there. The same steps as
// script/DeployGuard.sol on the EVM, re-runnable the same way: every step reads the chain first and
// is skipped once done, so an interrupted deploy is finished by running it again.

import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { id as keccakText, keccak256 } from "ethers";
import { create2Address, proxyInitCode, toBase58, toEvm, ZERO_SALT } from "./address.mjs";

const ZERO = "0x0000000000000000000000000000000000000000";
// IBittyV1Guard's constants.
export const PROTOCOL_CATEGORIES = { STAKING: 1, LENDING: 2, MARKET_TRADE: 3, INTENT: 4 };
const KEY_OWNER = keccakText("bitty.owner");
const KEY_GAS_WRAPPED = keccakText("bitty.gasWrapped");

/** The forge profile and output directory of every TRON build (foundry.toml `[profile.tron]`). */
const TRON_PROFILE = "tron";
const TRON_OUT = "out-tron";

export function forgeBuild(repo) {
  execFileSync("forge", ["build"], { cwd: repo, stdio: ["ignore", "inherit", "inherit"], env: { ...process.env, FOUNDRY_PROFILE: TRON_PROFILE } });
}

export function readArtifact(repo, file, contract = file.replace(/\.sol$/, "")) {
  const json = JSON.parse(readFileSync(join(repo, TRON_OUT, file, `${contract}.json`), "utf8"));
  return { abi: json.abi, bytecode: json.bytecode.object };
}

/** A `bytes constant NAME = hex"…";` pinned in a Solidity file. */
export function pinnedBytes(solFile, name) {
  const match = readFileSync(solFile, "utf8").match(new RegExp(`bytes constant ${name}\\s*=\\s*hex"([0-9a-fA-F]*)"`));
  if (!match) throw new Error(`${name} not found in ${solFile}`);
  return "0x" + match[1];
}

/**
 * Where the guard's three pieces land, given the network's CREATE2 deployer. The bootstrap and the
 * proxy are the pinned bytes the EVM guards were born with - only the deployer differs, and with it
 * every address. The implementation is this repo's TRON build (6-decimal native coin).
 */
export function planGuard({ repo, deployer, build = true }) {
  const at = (initCode) => create2Address(deployer, ZERO_SALT, initCode);
  const step = (name, initCode) => ({ name, address: at(initCode), initCode, initCodeHash: keccak256(initCode) });
  const pins = join(repo, "script/GuardBootstrapInitCode.sol");
  const bootstrap = step("BittyV1GuardBootstrap", pinnedBytes(pins, "GUARD_BOOTSTRAP_INITCODE"));
  const proxy = step("BittyV1GuardProxy", proxyInitCode(pinnedBytes(pins, "GUARD_PROXY_CREATIONCODE"), bootstrap.address));
  if (build) forgeBuild(repo);
  const implementation = step("BittyV1Guard", readArtifact(repo, "BittyV1Guard.sol").bytecode);
  // Deployed in this order: the proxy is born on the bootstrap, then upgraded to the implementation.
  return { deployer: toEvm(deployer), steps: [implementation, bootstrap, proxy], implementation, bootstrap, proxy };
}

/** The CREATE2 deployer, once per network. A plain deployment, so its address comes from the tx. */
export async function deployCreate2Deployer({ chain, repo, config, build = true }) {
  if (config.deployed.CREATE2_DEPLOYER) {
    const at = config.deployed.CREATE2_DEPLOYER.evm;
    if (!(await chain.hasCode(at))) throw new Error(`CREATE2_DEPLOYER recorded at ${toBase58(at)} but has no code there`);
    console.log(`CREATE2 deployer          already at ${toBase58(at)}`);
    return at;
  }
  if (build) forgeBuild(repo);
  const artifact = readArtifact(repo, "BittyTronCreate2Deployer.sol");
  const at = await chain.deployContract({ abi: artifact.abi, bytecode: artifact.bytecode, name: "BittyTronCreate2Deployer" });
  if (at) console.log(`CREATE2 deployer          deployed at ${toBase58(at)}`);
  return at;
}

/**
 * Create, upgrade, initialize, configure. `initialize` registers the network's assets and its
 * `protocols` (none until an adapter exists), and gates on tx.origin == DEPLOYER, as do the
 * bootstrap's upgrade - so only the DEPLOYER key can finish this.
 */
export async function deployGuard({ chain, plan, config }) {
  const id = await chain.chainId();
  if (id !== config.chainId) throw new Error(`connected to chain ${id}, ${config.network} is ${config.chainId}`);
  if (!chain.dryRun && chain.sender !== toEvm(config.DEPLOYER)) {
    throw new Error(`broadcasting key is ${chain.sender}; it must be the DEPLOYER ${config.DEPLOYER}`);
  }
  if (!(await chain.hasCode(plan.deployer))) throw new Error(`no CREATE2 deployer at ${toBase58(plan.deployer)}`);

  for (const s of plan.steps) {
    if (await chain.hasCode(s.address)) {
      console.log(`${s.name.padEnd(25)} already at ${toBase58(s.address)}`);
      continue;
    }
    await chain.send(plan.deployer, "function deploy(bytes32,bytes) payable returns (address)", [ZERO_SALT, s.initCode], {
      label: `deploy ${s.name}`,
    });
    if (!chain.dryRun && !(await chain.hasCode(s.address))) {
      throw new Error(`${s.name}: deployed, but nothing at the planned ${toBase58(s.address)} - the TVM CREATE2 math disagrees`);
    }
    console.log(`${s.name.padEnd(25)} deployed at ${toBase58(s.address)}`);
  }
  if (chain.dryRun && !(await chain.hasCode(plan.proxy.address))) {
    console.log("  [dry-run] the guard proxy does not exist yet, so its upgrade, initialize and config are all still to send");
    return;
  }

  const guard = plan.proxy.address;
  const tokens = (name) => toEvm(config.tokens[name] ?? name);

  const current = await chain.implementationOf(guard).catch(() => null);
  if (current === plan.implementation.address) console.log(`guard already on implementation ${toBase58(current)}`);
  else await chain.send(guard, "function upgradeToAndCall(address,bytes) payable", [plan.implementation.address, "0x"], { label: "guard.upgradeToAndCall" });

  const protocols = config.protocols ?? [];
  if ((await chain.read(guard, "function defaultAdmin() view returns (address)")) === ZERO) {
    await chain.send(
      guard,
      "function initialize(address[],uint8[],address[],uint8[])",
      [
        config.assets.map((a) => tokens(a.token)),
        config.assets.map((a) => a.category),
        protocols.map((p) => toEvm(p.address)),
        protocols.map((p) => PROTOCOL_CATEGORIES[p.category] ?? p.category),
      ],
      { label: "guard.initialize" },
    );
  } else {
    // Initialized on an earlier run: anything added to the config since goes in through the managers.
    const assets = [];
    for (const a of config.assets) {
      const live = await chain.read(guard, "function assetCategory(address) view returns (uint8)", [tokens(a.token)]);
      if (Number(live) !== a.category) assets.push(a);
    }
    if (assets.length) {
      await chain.send(guard, "function addAssets(address[],uint8[])", [assets.map((a) => tokens(a.token)), assets.map((a) => a.category)], {
        label: `guard.addAssets(${assets.map((a) => a.token).join(",")})`,
      });
    }
    const missing = [];
    for (const p of protocols) {
      if (!(await chain.read(guard, "function isProtocolRegistered(address) view returns (bool)", [toEvm(p.address)]))) missing.push(p);
    }
    if (missing.length) {
      await chain.send(
        guard,
        "function addProtocols(address[],uint8[])",
        [missing.map((p) => toEvm(p.address)), missing.map((p) => PROTOCOL_CATEGORIES[p.category] ?? p.category)],
        { label: `guard.addProtocols(${missing.map((p) => p.name ?? p.address).join(",")})` },
      );
    }
  }

  await setAddressIfUnset(chain, guard, KEY_OWNER, "CFG_OWNER", toEvm(config.DEPLOYER));
  await setAddressIfUnset(chain, guard, KEY_GAS_WRAPPED, "CFG_GAS_WRAPPED", tokens("WTRX"));

  for (const f of config.priceFeeds ?? []) {
    const asset = f.token === "native" ? ZERO : tokens(f.token);
    const quote = f.quote ? tokens(f.quote) : ZERO;
    const live = await chain.read(
      guard,
      "function priceFeed(address) view returns ((address feed,uint32 maxAge,uint8 decimals,uint8 assetDecimals,bool hasQuote,address quote))",
      [asset],
    );
    if (live.feed === toEvm(f.feed) && Number(live.maxAge) === f.maxAge && live.quote === quote) continue;
    await chain.send(guard, "function setPriceFeeds(address[],address[],uint32[],address[])", [[asset], [toEvm(f.feed)], [f.maxAge], [quote]], {
      label: `guard.setPriceFeeds(${f.token})`,
    });
  }
}

/** Kept, never overwritten: CFG_OWNER and CFG_GAS_WRAPPED are changed on purpose, not by a re-run. */
async function setAddressIfUnset(chain, guard, key, name, value) {
  const live = await chain.read(guard, "function getAddress(bytes32) view returns (address)", [key]);
  if (live !== ZERO) return console.log(`${name} already set, kept: ${toBase58(live)}`);
  await chain.send(guard, "function setAddress(bytes32,address)", [key, value], { label: `guard ${name}` });
}

export function outputs(plan) {
  const both = (a) => ({ evm: toEvm(a), base58: toBase58(a) });
  return {
    CREATE2_DEPLOYER: both(plan.deployer),
    BITTY_GUARD: both(plan.proxy.address),
    GUARD_IMPLEMENTATION: both(plan.implementation.address),
    GUARD_BOOTSTRAP: both(plan.bootstrap.address),
  };
}
