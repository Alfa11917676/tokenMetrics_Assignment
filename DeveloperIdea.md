# Design Rationale and Approach

The core idea behind this implementation is straightforward: the vault manages two strategies, one locked and one unlocked, and must support efficient deposits, withdrawals, and rebalancing across both.

During the design phase, I considered multiple approaches to handle deposits, withdrawals, and strategy rebalancing. The two primary approaches are outlined below.

## Approach 1: Priority Reimbursement During Rebalancing

In this approach, users deposit funds into the vault, after which the fund manager calls rebalance to distribute capital across the strategies according to the predefined allocation.

For withdrawals, two options are supported:

* **Instant Withdrawal**: Allows users to withdraw immediately, typically incurring a fee.
* **Standard Withdrawal**: Requires waiting for the bonding period of the locked strategy to complete.

For instant withdrawals, funds are sourced from:

* Newly deposited funds available in the contract, and
* Liquidity from the unlocked strategy.

Any shortfall created by instant withdrawals is resolved during the next rebalance cycle.

During rebalancing:

1. The unlocked strategy is reimbursed first to restore liquidity.
2. Remaining funds are distributed across strategies according to their target allocation.
3. The withdrawal batch is finalized, and pending withdrawals are processed.

This approach prioritizes liquidity restoration before allocation normalization.

## Approach 2: Capital-Aware Rebalancing (Chosen Implementation)

In this approach, users deposit funds and the fund manager triggers a rebalance to distribute capital across strategies.

Withdrawal options remain the same:

* **Instant Withdrawal** (with fees)
* **Standard Withdrawal** (post bonding period)

For instant withdrawals, funds are transferred only from newly deposited capital currently held by the vault, avoiding premature withdrawals from strategies.

During rebalancing:

1. The system first checks for any pending withdrawals from the previous batch.
2. It then iterates through the strategies (limited to two in this implementation).
3. Each strategy's current position is evaluated relative to the total effective capital:
   ```
   total capital = funds in vault
                + funds staked in strategies
                - funds reserved for withdrawals
   ```
4. Strategies are rebalanced based on their target weight:
   * If a strategy is underweight, additional funds are deposited.
   * If a strategy is overweight, funds are withdrawn.
5. Once allocations are corrected, the withdrawal batch is finalized and processed.

This approach ensures fair rebalancing based on real capital distribution while cleanly handling pending withdrawals.

## Notes on Implementation and Testing

This implementation is intended as a demonstration of the design concept rather than a production-ready system. While extensive testing has been performed, certain aspects may require further hardening, including:

* Additional edge case handling
* Expanded security checks
* Gas optimization refinements

Some potential vulnerabilities or edge cases may exist due to time constraints, and these would be addressed in a full production implementation.
