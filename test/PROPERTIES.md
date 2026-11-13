# GODS test properties

The existing deployment, mint event, factory, transfer, and administrative-selector
tests remain in `GODSToken.t.sol`. `GODSToken.properties.t.sol` adds allowance
lifecycle regressions and seven fuzz properties. `GODSToken.invariant.t.sol`
extends the existing independent ledger to include rejected actions.

## Discovery and evidence

The five discovery perspectives from the supplied Pashov fizz reference were
applied to the actual token and its vendored ERC-20 implementation. The Trail of
Bits property reference informed input bounds, pinned examples, and checks for
vacuous properties. These are local token tests; the supplied protected launch
checks were reviewed, but the pool/factory infrastructure they import is not part
of this repository and is not reproduced here.

| Perspective | Property and basis | Coverage |
| --- | --- | --- |
| Conservation | The supply is exactly `1_000_000_000 * 10**18`, and all balances sum to it. Required by the assignment; minted in `src/GODSToken.sol:10–14`. | Constant-supply invariant and independent balance ledger. |
| State transitions | Approval replaces the prior grant; only its owner/spender pair changes. Finite grants decrease on spending; unlimited grants remain unlimited. Rejected calls preserve state. See vendored `ERC20.sol:126–152,278–310`. | Allowance ledger, randomized rejection handlers, replacement/idempotence fuzzing, revocation and refill regressions. |
| Round trips | Sending tokens out and back restores balances exactly. Splitting a transfer has the same balance result as one transfer. No fees or conversion arithmetic exist in `GODSToken`; vendored `ERC20.sol:182–211` moves the specified integer amount. | Direct and delegated round-trip fuzzing, split-transfer equivalence, pinned one-wei example. |
| Adversarial actions | Neither another owner nor another spender's grant authorizes spending. Self-transfers still require sufficient balance, and delegated self-transfers still require allowance. See vendored `ERC20.sol:148–174,182–193,299–310`. | Wrong-owner, unapproved-spender, shared-balance, self-call, overdraft and maximum-value regressions; random unauthorized calls. |
| Token properties | Metadata stays fixed; transfers credit exactly the requested amount; zero recipients/spenders are rejected even for zero value. `GODSToken.sol:13` and vendored `ERC20.sol:165–174,278–285`. | Metadata invariant, arbitrary-recipient fuzzing, event checks, zero-address regressions and rejection handlers. |

`ERC20.sol` above is
`lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol`. Error selectors,
error precedence, unlimited approvals, and self-approval requirements are checks
of this pinned implementation's public behavior, not claims that every ERC-20
must implement those choices. No vault, staking, rounding, or lending properties
are applicable to this contract.

## Stateful campaign

- Four actors begin with equal shares of the actual constructor-minted supply.
  All successful transfers remain within that closed actor set, including self
  transfers. No token balances or allowances are set through storage cheatcodes.
- The independent ledger starts from the specified allocation and changes only
  after successful calls. Every actor balance and all 16 allowance pairs are
  compared with it after each handler call. Total supply, the balance sum,
  metadata, and balances/permissions of unapproved outside addresses are checked
  separately.
- Twelve targeted actions cover transfers, full-balance transfers, arbitrary and
  boundary approvals, delegated spending, and six kinds of rejection. Expected
  failures use low-level calls with explicit success/error assertions; they do
  not escape the handler as reverts. Preparatory approvals are recorded before
  a rejected delegated transfer, making allowance rollback observable.
- `approveAndSpend` selects a funded actor and spends a strictly positive amount
  with either an exact or unlimited grant. This prevents a campaign consisting
  only of zero-valued delegated transfers. `transferFrom` separately uses grants
  left by previous randomly ordered calls.
- Boundary approval choices include zero, one, the current balance, one above
  it, `uint256.max - 1`, and `uint256.max`. Invalid transfer amounts span the
  remaining `uint256` range. No generated case is discarded with `vm.assume`.
- Inline settings request 256 invariant sequences of depth 128 and 1,000 cases
  for each new fuzz property. Existing configuration is unchanged.

## Reproduction

No network, RPC, environment-derived addresses, or extra dependencies are needed.

```sh
forge build --out test/scratch/out --cache-path test/scratch/cache
FOUNDRY_FUZZ_SEED=0x34484aa485cf1dedc5c8e6143e84b505d25c38e2152de5cca61d54da30b13974 forge test --out test/scratch/out --cache-path test/scratch/cache
```

Scratch contains generated build artifacts only and is not required by the tests.
