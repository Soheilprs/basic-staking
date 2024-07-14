// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// Library containing utility functions and structures for staking operations.
library StakeLib {
    // Structure to hold all relevant information about a stake.
    struct StakeInformation {
        uint256 amount; // Amount of tokens staked.
        uint256 reward; // Accumulated reward tokens.
        uint256 apy; // Annual Percentage Yield as a percentage.
        uint256 startTime; // Timestamp when the stake was created.
        bool autoCompound; // Flag to enable or disable auto-compounding of rewards.
    }

    /// @notice Calculates the reward for a stake with optional compounding.
    /// @param stake The stake information.
    /// @return The calculated reward.
    function calculateReward(StakeInformation storage stake) internal view returns (uint256) {
        uint256 duration = block.timestamp - stake.startTime;
        uint256 periodCount = duration / 365 days; // Calculate full years elapsed

        if (periodCount > 0 && stake.autoCompound) {
            // Compounded interest calculation
            uint256 compoundedStakeAmount = stake.amount;
            for (uint256 i = 0; i < periodCount; i++) {
                uint256 reward = (compoundedStakeAmount * stake.apy) / 100;
                compoundedStakeAmount += reward; // Add reward to principal for next period
            }
            return compoundedStakeAmount - stake.amount; // Return total compounded amount minus original
        } else {
            // Simple interest calculation for less than one year or no compounding
            return (stake.amount * stake.apy * duration) / (365 days * 100);
        }
    }
}
