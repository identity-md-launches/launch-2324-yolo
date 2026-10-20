# yolo (YOLO)

Custom token for @moneycanbuy_fun. Solidity contract: `YoloToken` (`src/YoloToken.sol`).

## Behaviour
- Name `yolo`, symbol `YOLO`, 18 decimals.
- Supply: 1,000,000,000 YOLO (`1000000000000000000000000000` minor units), minted once to the
  deployer (`msg.sender`, the launch factory) in the constructor.
- Plain ERC-20: no owner, no mint, no burn, no transfer fee, no pause/blacklist. Supply can never change.
- An allowance of `type(uint256).max` is treated as infinite and not decremented.

## Deployment parameters
- Constructor arguments: none.
- Compiler: solc 0.8.26, optimizer 200 runs, `bytecode_hash = "none"`.
- Launch (decided by IMD): Ethereum (chain 1), paired with IMD
  `0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7`, fee 12500, tick spacing 60; economics
  `poolBps 6000`, initial market cap 2500 IMD, remainder to `0xee2aaa315cf7ed169f93148d30d24af9318dbb66`.

## Assumptions and operational responsibilities
- No admin keys exist; nothing needs configuring after launch ("After launch": nothing to set).
- The deployer receives the whole supply and is responsible for distributing it (the launch factory does this).
- Tests are not an audit.

## Checks
`forge build && forge test && forge fmt --check`
