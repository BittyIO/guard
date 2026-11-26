#!/usr/bin/env bash
# Sends a call through the governance timelock from the deployer key.
#
#   timelock.sh schedule     <chain> <target> <calldata> [salt]   queue a call
#   timelock.sh execute      <chain> <target> <calldata> [salt]   run it once its delay has passed
#   timelock.sh run          <chain> <target> <calldata>          schedule, wait the delay, execute
#   timelock.sh cancel       <chain> <operation id>               drop a queued call
#   timelock.sh status       <chain> <target> <calldata> [salt]   is it queued / ready / done
#   timelock.sh accept-admin <chain>                              the timelock accepts the guard admin
#
# <target> is an address, or "guard" for the Bitty guard. <calldata> comes from `cast calldata`, e.g.
#   timelock.sh run sepolia guard "$(cast calldata 'setUint(bytes32,uint256)' <key> 1)"
# The salt defaults to 0; a call identical to one already executed needs a different salt.
#
# The key is read from $PK and never printed. Set it with a hidden prompt (zsh):
#   read -s "PK?Private key: " && echo; export PK
# Needs: cast, and GOVERNANCE_TIMELOCK in deployments/<chain>.toml (written by GovernanceHandover).
set -euo pipefail
cd "$(dirname "$0")/../.."

GUARD=0x000000000F5fcD35885BfE4c700042cE7cb39554
ZERO=0x0000000000000000000000000000000000000000000000000000000000000000

usage() { sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }
[ $# -ge 2 ] || usage
cmd=$1 chain=$2

case $chain in
  sepolia) R=https://ethereum-sepolia-rpc.publicnode.com ;;
  *) echo "unknown chain: $chain (only sepolia has a timelock so far)" >&2; exit 1 ;;
esac
TL=$(grep -E '^GOVERNANCE_TIMELOCK *=' "deployments/$chain.toml" | cut -d'"' -f2 || true)
[ -n "$TL" ] || { echo "no GOVERNANCE_TIMELOCK in deployments/$chain.toml - run GovernanceHandover first" >&2; exit 1; }
DELAY=$(cast call "$TL" 'getMinDelay()(uint256)' --rpc-url "$R" | cut -d' ' -f1)

target() { [ "$1" = guard ] && echo $GUARD || echo "$1"; }
need_key() { [ -n "${PK:-}" ] || { echo "set PK first (see the header of this script)" >&2; exit 1; }; }
op_id() { cast call "$TL" 'hashOperation(address,uint256,bytes,bytes32,bytes32)(bytes32)' "$1" 0 "$2" $ZERO "$3" --rpc-url "$R"; }
send() { cast send "$TL" "$@" --rpc-url "$R" --private-key "$PK" | grep -E '^(status|transactionHash)'; }

state() { # <id> -> unset | waiting | ready | done
  local s
  s=$(cast call "$TL" 'getOperationState(bytes32)(uint8)' "$1" --rpc-url "$R")
  case $s in 0) echo unset ;; 1) echo waiting ;; 2) echo ready ;; 3) echo done ;; *) echo "state $s" ;; esac
}

schedule() { # <to> <data> <salt>
  need_key
  echo "schedule on $TL (delay ${DELAY}s): op $(op_id "$1" "$2" "$3")"
  send 'schedule(address,uint256,bytes,bytes32,bytes32,uint256)' "$1" 0 "$2" $ZERO "$3" "$DELAY"
}

execute() { # <to> <data> <salt>
  need_key
  local id s
  id=$(op_id "$1" "$2" "$3"); s=$(state "$id")
  [ "$s" = ready ] || { echo "op $id is $s, not ready - nothing sent" >&2; exit 1; }
  echo "execute op $id"
  send 'execute(address,uint256,bytes,bytes32,bytes32)' "$1" 0 "$2" $ZERO "$3"
}

wait_ready() { # <id>
  local s
  while :; do
    s=$(state "$1")
    [ "$s" = ready ] && return
    [ "$s" = waiting ] || { echo "op $1 is $s - stopping" >&2; exit 1; }
    sleep 10
  done
}

case $cmd in
  schedule) schedule "$(target "$3")" "$4" "${5:-$ZERO}" ;;
  execute) execute "$(target "$3")" "$4" "${5:-$ZERO}" ;;
  status) id=$(op_id "$(target "$3")" "$4" "${5:-$ZERO}"); echo "op $id: $(state "$id")" ;;
  cancel) need_key; echo "cancel op $3"; send 'cancel(bytes32)' "$3" ;;
  run)
    to=$(target "$3"); salt=$(cast keccak "$(date +%s)$RANDOM")
    schedule "$to" "$4" "$salt"
    echo "waiting ${DELAY}s for the delay (salt $salt)"
    wait_ready "$(op_id "$to" "$4" "$salt")"
    execute "$to" "$4" "$salt"
    ;;
  accept-admin)
    read -r pending at < <(cast call $GUARD 'pendingDefaultAdmin()(address,uint48)' --rpc-url "$R" | tr '\n' ' ')
    at=${at%% *}
    [ "$(echo "$pending" | tr '[:upper:]' '[:lower:]')" = "$(echo "$TL" | tr '[:upper:]' '[:lower:]')" ] \
      || { echo "the guard's pending admin is $pending, not the timelock - nothing sent" >&2; exit 1; }
    now=$(cast block --rpc-url "$R" -f timestamp latest)
    # The guard accepts strictly after `at`; the execute lands at least DELAY after the schedule.
    [ $((now + DELAY)) -gt "$at" ] \
      || { echo "too early: the guard accepts from $(date -r "$at") on - nothing sent" >&2; exit 1; }
    p=$(cast calldata 'acceptDefaultAdminTransfer()')
    id=$(op_id $GUARD "$p" $ZERO)
    [ "$(state "$id")" = unset ] && schedule $GUARD "$p" $ZERO
    echo "waiting ${DELAY}s for the delay"
    wait_ready "$id"
    execute $GUARD "$p" $ZERO
    echo "guard admin now: $(cast call $GUARD 'defaultAdmin()(address)' --rpc-url "$R")"
    ;;
  *) usage ;;
esac
