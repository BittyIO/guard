// The guard deploy against an in-memory chain: what is sent, in what order, and that a re-run sends
// nothing. No node and no key; the guard's own behaviour is forge's to test.

import { test } from "node:test";
import assert from "node:assert/strict";
import { toEvm } from "../lib/address.mjs";
import { deployGuard } from "../lib/guard.mjs";

const ZERO = "0x0000000000000000000000000000000000000000";
const addr = (n) => toEvm("0x" + n.toString(16).padStart(40, "0"));
const step = (name, n, code) => ({ name, address: addr(n), initCode: code, initCodeHash: "0x00" });

const DEPLOYER = addr(0x12ee);
const CREATE2 = addr(0xc2);
const ADAPTER = addr(0x201);

const config = () => ({
  network: "nile",
  chainId: 3448148188,
  DEPLOYER,
  tokens: { WTRX: addr(0xa1), USDT: addr(0xa2) },
  assets: [
    { token: "WTRX", category: 6 },
    { token: "USDT", category: 5 },
  ],
  protocols: [],
  priceFeeds: [
    { token: "native", feed: addr(0xf1), maxAge: 90000 },
    { token: "WTRX", feed: addr(0xf1), maxAge: 90000 },
  ],
  deployed: {},
});

const implementation = step("BittyV1Guard", 0x101, "0x01");
const bootstrap = step("BittyV1GuardBootstrap", 0x102, "0x02");
const proxy = step("BittyV1GuardProxy", 0x103, "0x03");
const plan = { deployer: CREATE2, steps: [implementation, bootstrap, proxy], implementation, bootstrap, proxy };

/** Just enough of a TRON node and the guard behind its proxy. */
class FakeChain {
  constructor() {
    this.dryRun = false;
    this.sender = DEPLOYER;
    this.code = new Set([CREATE2]);
    this.impl = ZERO;
    this.admin = ZERO;
    this.assets = new Map();
    this.protocols = new Map();
    this.config = {};
    this.feeds = {};
    this.sent = [];
  }
  async chainId() {
    return 3448148188;
  }
  async hasCode(a) {
    return this.code.has(a);
  }
  async implementationOf() {
    return this.impl;
  }
  async read(to, sig, args = []) {
    const name = sig.match(/function (\w+)/)[1];
    if (name === "defaultAdmin") return this.admin;
    if (name === "assetCategory") return BigInt(this.assets.get(args[0]) ?? 0);
    if (name === "isProtocolRegistered") return this.protocols.has(args[0]);
    if (name === "getAddress") return this.config[args[0]] ?? ZERO;
    if (name === "priceFeed") return this.feeds[args[0]] ?? { feed: ZERO, maxAge: 0n, quote: ZERO };
    throw new Error(`unexpected read ${name}`);
  }
  async send(to, sig, args = [], { label } = {}) {
    const name = sig.match(/function (\w+)/)[1];
    this.sent.push(label ?? name);
    if (this.dryRun) return;
    if (name === "deploy") return this.code.add(plan.steps.find((s) => s.initCode === args[1]).address);
    if (name === "upgradeToAndCall") return (this.impl = args[0]);
    if (name === "initialize") {
      this.admin = DEPLOYER;
      args[0].forEach((a, i) => this.assets.set(a, args[1][i]));
      args[2].forEach((p, i) => this.protocols.set(p, args[3][i]));
      return;
    }
    if (name === "addAssets") return args[0].forEach((a, i) => this.assets.set(a, args[1][i]));
    if (name === "addProtocols") return args[0].forEach((p, i) => this.protocols.set(p, args[1][i]));
    if (name === "setAddress") return (this.config[args[0]] = args[1]);
    if (name === "setPriceFeeds") return (this.feeds[args[0][0]] = { feed: args[1][0], maxAge: BigInt(args[2][0]), quote: args[3][0] });
    throw new Error(`unexpected send ${name}`);
  }
}

const quiet = async (fn) => {
  const log = console.log;
  console.log = () => {};
  try {
    return await fn();
  } finally {
    console.log = log;
  }
};

test("a first deploy: three pieces, upgrade, initialize, owner, gas token, feeds", async () => {
  const chain = new FakeChain();
  await quiet(() => deployGuard({ chain, plan, config: config() }));
  assert.deepEqual(chain.sent, [
    "deploy BittyV1Guard",
    "deploy BittyV1GuardBootstrap",
    "deploy BittyV1GuardProxy",
    "guard.upgradeToAndCall",
    "guard.initialize",
    "guard CFG_OWNER",
    "guard CFG_GAS_WRAPPED",
    "guard.setPriceFeeds(native)",
    "guard.setPriceFeeds(WTRX)",
  ]);
  assert.equal(chain.impl, implementation.address);
  assert.equal(chain.assets.get(addr(0xa2)), 5);
  assert.equal(chain.protocols.size, 0);
});

test("a re-run sends nothing", async () => {
  const chain = new FakeChain();
  await quiet(() => deployGuard({ chain, plan, config: config() }));
  chain.sent = [];
  await quiet(() => deployGuard({ chain, plan, config: config() }));
  assert.deepEqual(chain.sent, []);
});

test("an adapter added to the config later is registered with addProtocols, and nothing else is sent", async () => {
  const chain = new FakeChain();
  await quiet(() => deployGuard({ chain, plan, config: config() }));
  chain.sent = [];
  const later = { ...config(), protocols: [{ name: "SunSwapV3TradeProtocol", address: ADAPTER, category: "MARKET_TRADE" }] };
  await quiet(() => deployGuard({ chain, plan, config: later }));
  assert.deepEqual(chain.sent, ["guard.addProtocols(SunSwapV3TradeProtocol)"]);
  assert.equal(chain.protocols.get(ADAPTER), 3);
});

test("a dry run from nothing sends nothing and stops before reading a guard that is not there", async () => {
  const chain = new FakeChain();
  chain.dryRun = true;
  chain.sender = null;
  await quiet(() => deployGuard({ chain, plan, config: config() }));
  assert.deepEqual(chain.sent, ["deploy BittyV1Guard", "deploy BittyV1GuardBootstrap", "deploy BittyV1GuardProxy"]);
  assert.equal(chain.code.size, 1);
});

test("only the DEPLOYER key may broadcast", async () => {
  const chain = new FakeChain();
  chain.sender = addr(0xbad);
  await assert.rejects(() => quiet(() => deployGuard({ chain, plan, config: config() })), /must be the DEPLOYER/);
});

test("the wrong network is refused before anything is sent", async () => {
  const chain = new FakeChain();
  chain.chainId = async () => 728126428;
  await assert.rejects(() => quiet(() => deployGuard({ chain, plan, config: config() })), /connected to chain 728126428/);
  assert.deepEqual(chain.sent, []);
});
