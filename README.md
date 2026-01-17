# Multi-Strategy ERC-4626 Vault

A sophisticated ERC-4626 compliant vault that allocates assets across multiple strategies, supporting both liquid and locked strategies with a withdrawal queue mechanism.

## Architecture Overview

The system consists of several key components:

- **MockUSDC**: ERC20 token with 6 decimals for testing
- **BaseStrategy Interface**: Defines the interface for strategy contracts
- **MockERC4626Strategy**: Liquid strategy implementing ERC4626 (always withdrawable)
- **MockLockedStrategy**: Strategy with lockup period extending MockERC4626Strategy
- **MultiStrategyVault**: Main vault contract inheriting ERC4626, AccessControl, and Pausable

### Data Flow

```
User Deposit → Vault (idle USDC) → Rebalance → Strategies (ERC4626)
User Withdraw → Vault (liquid USDC) → If insufficient → Queue → Claim after unlock
```

## Key Features

### 1. Multi-Strategy Allocation

The vault supports multiple strategies, each with configurable allocation percentages:
- Allocations are set in basis points (BPS), where 10,000 = 100%
- Maximum allocation per strategy: 5,000 BPS (50%)
- Total allocations must sum to 10,000 BPS (100%)

### 2. Rebalancing

The `rebalance()` function moves funds across strategies to match target allocations:
- Calculates target assets for each strategy based on `totalAssets()` and allocation percentages
- Deposits funds into underweight strategies
- Withdraws from overweight strategies (only if not locked)
- Locked strategies are skipped during withdrawal, even if overweight

### 3. Withdrawal Queue

The vault implements a sophisticated withdrawal queue for handling locked strategies:

**Immediate Withdrawal Flow:**
1. User calls `withdraw()` or `redeem()`
2. Shares are burned immediately (no pending shares)
3. If sufficient liquid USDC is available, user receives assets immediately
4. If insufficient, partial payment is made and remainder is queued

**Queued Withdrawal Flow:**
1. User receives a `requestId` for the queued portion
2. User must wait until all locked strategies unlock
3. User calls `claimWithdraw(requestId)` to receive remaining assets
4. System verifies all locked strategies are unlocked before transfer

### 4. ERC-4626 Compliance

The vault fully implements the ERC-4626 standard:
- `totalAssets()` includes idle USDC + strategy assets (via `convertToAssets`)
- Share pricing reflects yield from strategies
- All standard ERC-4626 functions are supported

### 5. Access Control

Two roles are defined:
- **DEFAULT_ADMIN_ROLE**: Can add strategies, pause/unpause
- **MANAGER_ROLE**: Can set allocations and trigger rebalancing

### 6. Pause Functionality

The vault can be paused to block:
- Deposits (`deposit()`, `mint()`)
- Rebalancing (`rebalance()`)

Withdrawals remain functional when paused, allowing users to exit during emergencies.

## Usage

### Setup

1. Deploy the vault with USDC asset, admin, and manager addresses
2. Add strategies using `addStrategy(strategy, allocationBps)`
3. Set initial allocations using `setAllocations([...])`

### Depositing

```solidity
usdc.approve(address(vault), amount);
vault.deposit(amount, receiver);
```

### Rebalancing

```solidity
vault.setAllocations([6000, 4000]); // 60/40 split
vault.rebalance();
```

### Withdrawing

**Immediate withdrawal (if sufficient liquidity):**
```solidity
vault.withdraw(assets, receiver, owner);
// or
vault.redeem(shares, receiver, owner);
```

**Queued withdrawal (if strategies are locked):**
```solidity
uint256 requestId = vault.requestWithdraw(shares);
// ... wait for strategies to unlock ...
vault.claimWithdraw(requestId);
```

## Known Limitations

1. **Locked Strategy Withdrawals**: During rebalancing, locked strategies cannot be withdrawn from even if overweight. Funds remain in the strategy until unlock.

2. **No Auto-Routing on Deposit**: Deposits go to idle USDC balance. Manual rebalancing is required to route funds to strategies.

3. **No Fees**: The vault does not charge any fees. All yield accrues to shareholders.

4. **Withdrawal Queue Dependency**: Users with queued withdrawals must wait for ALL locked strategies to unlock, even if their specific withdrawal doesn't require funds from those strategies.

5. **Single Asset**: The vault currently supports only USDC (6 decimals). Multi-asset support would require significant architectural changes.

## Testing

Run tests with:
```bash
forge test
```

Test coverage includes:
- Deposit functionality and share minting
- Allocation setting and rebalancing
- Yield generation and share price appreciation
- Withdrawal queue with locked strategies

## Security Considerations

- Shares are burned immediately on withdrawal request (no pending shares)
- Reentrancy protection via checks-effects-interactions pattern
- Access control on sensitive functions
- Pause functionality for emergency stops
- Withdrawals remain available when paused

## License

MIT
