#!/usr/bin/env bash
# Read-only: who holds Bitty's powers on one chain. Run before and after the handover.
#
#   check.sh <chain>
#
# Prints the guard admin and any pending transfer, who holds each manager role, CFG_OWNER, the
# factory and forwarder owners, and - once GOVERNANCE_TIMELOCK is in deployments/<chain>.toml -
# the timelock's delay and roles. Ends with PASS only when the deployer holds nothing on the guard
# and drives the timelock alone.
set -uo pipefail
cd "$(dirname "$0")/../.."
[ $# -ge 1 ] || { sed -n '2,4p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }
chain=$1

G=0x000000000F5fcD35885BfE4c700042cE7cb39554
D=0x12EE2de7BF086388B1D560eb95e7191Edfab9823
FWD=0xD6013C5e339cd3546c0c7E86c306554a63FbAa6F
case $chain in
  sepolia) R=https://ethereum-sepolia-rpc.publicnode.com ;;
  base-sepolia) R=https://base-sepolia-rpc.publicnode.com ;;
  mainnet) R=https://ethereum-rpc.publicnode.com ;;
  base) R=https://base-rpc.publicnode.com ;;
  arbitrum) R=https://arbitrum-one-rpc.publicnode.com ;;
  bsc) R=https://bsc-rpc.publicnode.com ;;
  robinhood) R=https://rpc.mainnet.chain.robinhood.com ;;
  *) echo "unknown chain: $chain"; exit 1 ;;
esac
TL=$(grep -E '^GOVERNANCE_TIMELOCK *=' "deployments/$chain.toml" 2>/dev/null | cut -d'"' -f2)
FACTORY=$(grep -hE '^BITTY_VAULT_FACTORY *=' "../vault/deployments/$chain.toml" 2>/dev/null | cut -d'"' -f2)
call() { cast call "$@" --rpc-url "$R" 2>/dev/null | head -1 | cut -d' ' -f1; }
fail=0
lc() { echo "$1" | tr "[:upper:]" "[:lower:]"; }
bad() { echo "  !! $1"; fail=1; }

admin=$(call $G 'defaultAdmin()(address)')
pend=$(cast call $G 'pendingDefaultAdmin()(address,uint48)' --rpc-url "$R" | tr '\n' ' ')
owner=$(call $G 'getAddress(bytes32)(address)' "$(cast keccak bitty.owner)")
echo "== $chain"
echo "guard admin        $admin"
echo "pending admin      $pend"
[ "$(lc "$admin")" = "$(lc $D)" ] && bad "deployer is still the guard admin"
for r in ASSET_MANAGER_ROLE PROTOCOL_MANAGER_ROLE IMPLEMENTATION_MANAGER_ROLE CONFIG_MANAGER_ROLE; do
  h=$(cast keccak $r)
  dep=$(call $G 'hasRole(bytes32,address)(bool)' "$h" $D)
  tl="-"; [ -n "$TL" ] && tl=$(call $G 'hasRole(bytes32,address)(bool)' "$h" "$TL")
  printf '%-28s deployer=%-5s timelock=%s\n' $r "$dep" "$tl"
  [ "$dep" = true ] && bad "deployer still holds $r"
done
echo "CFG_OWNER          $owner"
[ "$(lc "$owner")" = "$(lc $D)" ] && bad "CFG_OWNER is still the deployer"
fo=$(call $FWD 'owner()(address)'); echo "forwarder owner    $fo"
[ -n "$TL" ] && [ "$(lc "$fo")" != "$(lc "$TL")" ] && bad "forwarder owner is not the timelock"
[ -n "$FACTORY" ] && echo "factory owner      $(call "$FACTORY" 'owner()(address)')"
if [ -n "$TL" ]; then
  echo "timelock           $TL  delay=$(call "$TL" 'getMinDelay()(uint256)')s"
  echo "timelock self-admin $(call "$TL" 'hasRole(bytes32,address)(bool)' 0x0000000000000000000000000000000000000000000000000000000000000000 "$TL")  deployer-admin $(call "$TL" 'hasRole(bytes32,address)(bool)' 0x0000000000000000000000000000000000000000000000000000000000000000 $D)"
  for r in PROPOSER_ROLE EXECUTOR_ROLE CANCELLER_ROLE; do
    v=$(call "$TL" 'hasRole(bytes32,address)(bool)' "$(cast keccak $r)" $D)
    echo "  deployer $r: $v"
    [ "$v" = true ] || bad "deployer lacks the timelock $r"
  done
fi
[ $fail = 0 ] && echo "PASS: the deployer holds nothing on $chain" || echo "NOT DONE on $chain"
