# GODS OF IMD (GODS)

A fixed-supply ERC-20 for the IdentityMD custom token launch. The only production
contract is [`GODSToken`](src/GODSToken.sol).

| Parameter | Value |
| --- | --- |
| Solidity contract identifier | `GODSToken` |
| Token name | `GODS OF IMD` |
| Token symbol | `GODS` |
| Decimals | `18` |
| Supply in whole tokens | `1,000,000,000` |
| Supply in smallest units | `1000000000000000000000000000` (`10^27`) |
| Constructor arguments | None |
| Constructor transaction value | `0` |
| Initial recipient | Immediate deployer, `msg.sender` |
| Launch chain | Ethereum, chain ID `1` |

## Design and assumptions

The constructor sets the name and symbol, then mints `INITIAL_SUPPLY` once. It
emits `Transfer(address(0), deployer, INITIAL_SUPPLY)`. The token inherits the
standard OpenZeppelin ERC-20 implementation with 18 decimals. There is no exposed
mint or burn function, so total supply stays constant after construction.

The brief specifies no special transfer rules. Accordingly, transfers move the
exact requested amount with no token tax, fee, rebasing, or callbacks. There is
no owner, pause, blacklist, confiscation, initialization, upgrade, proxy, or
external configuration. The constructor does not call any other contract.

`transfer`, `approve`, and `transferFrom` return `true` on success and revert on
failure with OpenZeppelin's ERC-6093 custom errors. Zero-value transfers between
valid addresses succeed and emit `Transfer`. Self-transfers preserve the balance.
Transfers involving a zero sender or recipient and approvals to a zero spender
are rejected. Failed transfers roll back balances and allowance consumption.

`approve` replaces the caller's existing allowance. Finite allowances decrease
when spent; `type(uint256).max` represents an unlimited allowance and does not
decrease. OpenZeppelin v5 emits `Approval` for `approve`, but does not emit it
when `transferFrom` spends an allowance. Integrations should read `allowance`
instead of reconstructing it exclusively from events. No permit extension is
included.

## Build and test

Run from the repository root with Foundry and Solidity `0.8.26` available:

```sh
forge build
FOUNDRY_FUZZ_SEED=0x34484aa485cf1dedc5c8e6143e84b505d25c38e2152de5cca61d54da30b13974 forge test
forge fmt --check
```

`foundry.toml` pins Solidity `0.8.26`, Cancun EVM, optimizer enabled with 200
runs, and `bytecode_hash = "none"`. It enables neither FFI nor filesystem
permissions. All imported dependencies and their licenses are ordinary files
under `lib/`; no package installation, submodule, RPC endpoint, key, or environment
configuration is required by the tests. The compiler must already be installed
for an offline build.

The unit and fuzz tests cover metadata, supply, the mint event, CREATE2 deployment
by a factory, exact transfers, self/zero/full-balance transfers, allowance
replacement, revocation, infinite approval, unauthorized spending, error cases,
atomic rollback, and rejection of mint/admin calls. Stateful invariants exercise
transfers and approvals among four holders and compare balances and allowances
with an independent ledger. Defaults are 256 cases per fuzz test and 128 invariant
runs with 64 actions each. Tests use isolated EVM state and do not read or change
environment variables.

The local launch-flow test simulates token transfers for allocation, claims, and
trading. It does not instantiate Uniswap or validate pool pricing. The supplied
protected launch harness depends on separate factory/pool sources and launch
configuration; it is the network verifier's integration check, not part of this
standalone project's test suite.

## Deployment parameters and responsibilities

Deploy the creation bytecode for `src/GODSToken.sol:GODSToken` with no appended
constructor arguments and no ETH. The build artifact is
`out/GODSToken.sol/GODSToken.json`. It has no linked library addresses or
initialization transaction. Deploy it directly, not behind a proxy.

For the requested launch, the IdentityMD factory is the immediate deployer and
receives all `10^27` units. The wallet initiating the factory call receives no
constructor allocation. The factory subsequently handles the specified 10%
swarm allocation, 85% pool allocation, and 5% remainder allocation. Those
allocations and the pool economics are launch responsibilities; the token does
not reserve balances or perform them in its constructor. The later manifest step
records the contract identifier, supply, constructor arguments, and economics.
No launch manifest is supplied by this project.

The launch operator must use the pinned build settings, complete the network's
integration and independent security review, deploy through the designated
factory, verify the deployed source/bytecode, and confirm metadata, supply, and
allocation balances. This repository does not broadcast transactions.

## After launch

There are no settings, setters, privileged accounts, or maintenance transactions.
The deployer has the same transfer rights as every other holder after distribution.
Holders manage their tokens and spender approvals. Prefer allowances limited to
the intended spend; when replacing an existing nonzero allowance, first revoke it
and confirm the revocation to mitigate the standard ERC-20 approval race.

Transfers do not check whether a recipient contract can recover tokens. Tokens
sent to the token contract itself or another unrecoverable address cannot be
rescued by an administrator. Ordinary ETH payments are rejected; forcibly sent
ETH or unrelated tokens have no recovery function.

The implementation was reviewed against the supplied security reference for
supply conservation, authorization, arithmetic, external calls, and privileged
operations. Foundry build, unit/fuzz tests, and stateful invariants are the local
validation tools. No Slither or Mythril analysis or independent audit is claimed.

## Dependencies

- [OpenZeppelin Contracts v5.1.0](https://github.com/OpenZeppelin/openzeppelin-contracts/tree/v5.1.0):
  the ERC-20 import closure and MIT license.
- [forge-std v1.9.7](https://github.com/foundry-rs/forge-std/tree/v1.9.7):
  the `Test.sol` import closure and MIT/Apache-2.0 licenses; test use only.

[`DEPENDENCIES.json`](DEPENDENCIES.json) lists the pinned source URLs and SHA-256
hashes of the delivered dependency files. Sources were retrieved as text; blank
line formatting may differ from upstream. No dependency update is performed by
the build.
