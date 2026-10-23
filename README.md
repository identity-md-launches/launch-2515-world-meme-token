# World Meme Token (WORLD)

A fixed-supply ERC-20 for an IdentityMD custom token launch on Ethereum (chain id 1).

| Parameter | Value |
|-----------|-------|
| Solidity contract | `WorldMemeToken` (`src/WorldMemeToken.sol`) |
| `name()` | `World Meme Token` |
| `symbol()` | `WORLD` |
| `decimals()` | `18` |
| Total supply | 1,000,000,000 WORLD = `1000000000000000000000000000` minor units (1e27) |
| Constructor arguments | none |
| Minted to | `msg.sender` of the constructor, once, in the constructor |
| Owner / admin | none |

## Behaviour

- The constructor mints the entire supply to `msg.sender` and emits the standard `Transfer`
  from the zero address plus a `SupplyMinted(deployer, amount)` event. Nothing else is minted,
  ever: there is no `mint`, no minter role, no owner and no upgrade path.
- Transfers, approvals and `transferFrom` are OpenZeppelin's audited ERC20 v5.1.0 behaviour,
  unchanged. There is no transfer tax, burn-on-transfer, reflection, pause, blacklist, freeze,
  lock or seize. Every transfer delivers exactly the amount sent.
- The contract has no `receive` or `fallback`, so it rejects ether and unknown calls.
- The runtime contains no `DELEGATECALL`, `CALLCODE` or `SELFDESTRUCT`.

## Assumptions

- "The deployer" means the address that executes the constructor. On the IdentityMD launch that
  is the ProjectFactory, which then distributes the supply itself (see below). Under a direct
  deployment it is whichever account sends the creation transaction.
- Supply is fixed for the life of the contract. The supply can only ever decrease if holders
  send tokens to an address nobody controls; the contract offers no burn function.
- The constructor makes no external calls and needs no deployed contracts, so it deploys on an
  empty chain and under the launch's CREATE2 flow.
- No value in this token depends on the requester: there are no fees, rates, prices or outside
  addresses. The deployment carries no placeholders.

## Launch parameters (decided by the launch, not by this repository)

These are copied here for the reviewer's reference. The manifest step writes `launch.json`
after this work is accepted; this repository deliberately contains no manifest.

- Chain: Ethereum, chain id 1.
- Pair currency: IMD, `0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7` (18 decimals).
- Pool fee 12500 (1.25%), tick spacing 60, initial price `79228162514264337593543950336`.
- Economics: `poolBps` 8000, `initialMarketCapWei` `4300000000000000000000` (4,300 IMD for the
  whole supply), `remainderTo` `0x5873ba51e1fe4a03d1b74528f60678885de4e765`.
- Supply split performed by the factory from the minted balance: 10% to the launch's
  MerkleDistributor (the swarm), 80% seeds the single-sided Uniswap v4 pool, 10% is forwarded to
  `remainderTo`. The token itself has no knowledge of these addresses and needs none, because it
  taxes nothing.

## Deployment

The IdentityMD deployer launches the token through the factory from the bytecode as built here.
Nothing in this repository broadcasts a transaction or holds a key.

`script/DeployWorldMemeToken.s.sol` is a reviewable reference deployment for a local fork or a
dry run. Its `deploy()` function is what the tests call; `run()` only wraps it in a broadcast.
It reads no environment variables and takes no arguments, because the token has none.

```sh
forge script script/DeployWorldMemeToken.s.sol --rpc-url <anvil or fork url> --broadcast
```

Whoever broadcasts receives the whole supply.

## After launch

There is nothing to configure. The token has no owner, no setters and no stored outside
addresses. Operational responsibilities after launch are:

- **Holding the supply safely.** On the launch flow the factory distributes the full balance in
  the same transaction. Under any other deployment, the deployer's key controls the entire
  supply until it is moved.
- **Explorer verification.** Verifying the source on Etherscan belongs to the network's deployer
  and the launch policy, using the compiler settings in `foundry.toml` (solc 0.8.26, optimizer
  on, 200 runs, `bytecode_hash = "none"`).
- **Nothing to pause or recover.** Because there are no privileged functions, there is no
  emergency lever. Tokens sent to a wrong address cannot be recovered by anyone. Holders are
  responsible for their own approvals; revoke an allowance by calling `approve(spender, 0)`.

## Trust and security notes

- Trust surface: none beyond the ERC-20 standard. No role can mint, move, freeze or seize a
  holder's balance, so the launch floor's "privileged hand" checks have nothing to find.
- Approval race: like every standard ERC-20, changing a non-zero allowance to another non-zero
  value is subject to the classic front-running pattern. Set to zero first if that matters.
- The `eth-security` checklist was applied while writing. Items that do not apply to a
  fixed-supply token with no external calls: reentrancy, oracle manipulation, decimal mixing,
  SafeERC20 (this token returns `bool` as the standard requires), access control and
  upgradeability.
- Tools run here: `forge build`, `forge test` (including fuzz runs with the verifier's seed) and
  `forge fmt --check`. Slither was not available on this machine and was not run. Passing tests
  are not an audit; an independent adversarial review before release is still recommended.

## Repository layout

```
foundry.toml                     compiler pins and build settings
remappings.txt                   forge-std and OpenZeppelin remappings
src/WorldMemeToken.sol           the token
script/DeployWorldMemeToken.s.sol reference deploy script
test/WorldMemeToken.t.sol        behaviour, failure and fuzz tests
test/DeployWorldMemeToken.t.sol  calls the script's deploy() directly
lib/forge-std                    vendored forge-std v1.9.7 (MIT / Apache-2.0)
lib/openzeppelin                 vendored OpenZeppelin Contracts v5.1.0 (MIT), contracts only
```

Dependencies are committed as ordinary files, not git submodules, so the project builds offline.

## Building and testing

```sh
forge build
forge test
forge fmt --check
```

The verifier runs fuzz tests with a fixed seed; to reproduce:

```sh
FOUNDRY_FUZZ_SEED=0x8066c9eb0d2af20191551d8059401d732c634215305b95079b0e316e0e8cf3c3 forge test
```
