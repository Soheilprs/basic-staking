// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {StakeTokens} from "../src/StakeTokens.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {StakeLib} from "../src/libraries/StakeLib.sol";

contract StakeTokensTest is Test {
    StakeTokens public stakeTokens;

    MockERC20 public token0;
    MockERC20 public token1;
    MockERC20 public token2;
    MockERC20 public rewardToken;

    address public user = address(1);
    uint256 public stakeAmount = 1000e18;
    uint256 public token0APY = 10;
    uint256 public token1APY = 15;
    uint256 public token2APY = 20;

    event Staked(address indexed user, address tokenAddress, uint256 amount, bool autoCompound);
    event UnStaked(address indexed user, address tokenAddress, uint256 amount);
    event RewardWithdrawn(address indexed user, address tokenAddress, uint256 amount);

    // Setup the testing environment
    function setUp() public {
        token0 = new MockERC20("Token0", "TKN0");
        token1 = new MockERC20("Token1", "TKN1");
        token2 = new MockERC20("Token2", "TKN2");
        rewardToken = new MockERC20("RewardToken", "RWD");

        // Deploy the StakeTokens contract
        vm.startBroadcast();
        stakeTokens = new StakeTokens(
            address(token0), address(token1), address(token2), address(rewardToken), token0APY, token1APY, token2APY
        );
        vm.stopBroadcast();

        // Mint tokens for the user and reward tokens for the contract
        token0.mint(user, stakeAmount);
        token1.mint(user, stakeAmount);
        token2.mint(user, stakeAmount);
        token0.mint(address(stakeTokens), stakeAmount);
        token1.mint(address(stakeTokens), stakeAmount);
        token2.mint(address(stakeTokens), stakeAmount);
        rewardToken.mint(address(stakeTokens), stakeAmount * 100);

        // Approve the StakeTokens contract to spend the user's tokens
        vm.startPrank(user);
        token0.approve(address(stakeTokens), stakeAmount);
        token1.approve(address(stakeTokens), stakeAmount);
        token2.approve(address(stakeTokens), stakeAmount);
        vm.stopPrank();
    }

    // Test the staking functionality
    function testStake() public {
        vm.startPrank(user);

        console.log("Stake token contract address", address(stakeTokens));
        console.log("Token 0 address", address(token0));
        vm.expectEmit(true, true, true, false);
        emit Staked(address(user), address(token0), stakeAmount, false);
        stakeTokens.stake(address(token0), stakeAmount, false);

        // Verify the staking results
        (uint256 amount, uint256 reward,,,) = stakeTokens.stakes(user, address(token0));
        assertEq(amount, stakeAmount);
        assertEq(reward, 0);

        vm.stopPrank();
    }

    // Test the unstaking functionality
    function testUnstake() public {
        vm.startPrank(user);

        console.log("Stake token contract address", address(stakeTokens));
        console.log("Token 0 address", address(token0));

        vm.expectEmit(true, true, true, false);
        emit Staked(address(user), address(token0), stakeAmount, false);
        stakeTokens.stake(address(token0), stakeAmount, false);

        // Advance time by 365 days
        vm.warp(block.timestamp + 365 days);

        uint256 expectedReward = (stakeAmount * token0APY * 365 days) / (365 days * 100);

        vm.expectEmit(true, true, true, false);
        emit UnStaked(address(user), address(token0), stakeAmount);
        // Unstake the tokens
        stakeTokens.unstake(address(token0));

        // Verify the unstaking results
        uint256 userBalance = token0.balanceOf(user);
        assertEq(userBalance, stakeAmount + expectedReward);
        vm.stopPrank();
    }

    // Test withdrawing rewards
    function testWithdrawReward() public {
        vm.startPrank(user);

        vm.expectEmit(true, true, true, false);
        emit Staked(address(user), address(token0), stakeAmount, false);
        stakeTokens.stake(address(token0), stakeAmount, false);

        // Advance time by 365 days
        vm.warp(block.timestamp + 365 days);

        // Withdraw the rewards
        uint256 initialRewardBalance = rewardToken.balanceOf(user);

        vm.expectEmit(true, true, true, false);
        emit RewardWithdrawn(user, address(0), stakeAmount);
        stakeTokens.withdrawReward(address(token0));

        // Calculate the expected reward
        uint256 reward = (stakeAmount * token0APY * 365 days) / (365 days * 100);
        uint256 finalRewardBalance = rewardToken.balanceOf(user);
        assertEq(finalRewardBalance, initialRewardBalance + reward);

        vm.stopPrank();
    }

    // Test staking with auto-compound set to true
    function testStakeAutoCompoundTrue() public {
        vm.startPrank(user);

        vm.expectEmit(true, true, true, false);
        emit Staked(address(user), address(token0), stakeAmount, false);
        stakeTokens.stake(address(token1), stakeAmount, true);

        // Verify the staking results
        (uint256 amount, uint256 reward,,,) = stakeTokens.stakes(user, address(token1));
        assertEq(amount, stakeAmount);
        assertEq(reward, 0);

        vm.stopPrank();
    }

    // Test staking with auto-compound set to false
    function testStakeAutoCompoundFalse() public {
        vm.startPrank(user);

        vm.expectEmit(true, true, true, false);
        emit Staked(address(user), address(token0), stakeAmount, false);
        stakeTokens.stake(address(token1), stakeAmount, false);

        // Verify the staking results
        (uint256 amount, uint256 reward,,, bool autoCompound) = stakeTokens.stakes(user, address(token1));
        assertEq(amount, stakeAmount);
        assertEq(reward, 0);
        assertEq(autoCompound, false);

        vm.stopPrank();
    }

    // Test unstaking with auto-compound set to false after one period
    function testUnstakeAutoCompoundFalseAfterOnePeriod() public {
        vm.startPrank(user);

        vm.expectEmit(true, true, true, false);
        emit Staked(address(user), address(token0), stakeAmount, false);
        stakeTokens.stake(address(token0), stakeAmount, false);

        // Advance time by 365 days
        vm.warp(block.timestamp + 365 days);

        // Calculate the expected reward
        uint256 expectedReward = compoundInterest(stakeAmount, token0APY, 1, false);

        // Verify the staking results before unstaking
        (uint256 amount, uint256 reward,,,) = stakeTokens.stakes(user, address(token0));

        uint256 expectedTotal = stakeAmount + expectedReward;

        console.log("Stake amount", stakeAmount / 10e18);
        console.log("Expected reward", expectedReward / 10e18);
        console.log("Expected total", expectedTotal / 10e18);

        assertEq(amount, stakeAmount);
        assertEq(reward, 0);

        // Unstake the tokens
        vm.expectEmit(true, true, true, false);
        emit UnStaked(address(user), address(token0), stakeAmount);
        stakeTokens.unstake(address(token0));

        // Verify the unstaking results
        uint256 userBalance = token0.balanceOf(user);
        assertEq(userBalance, stakeAmount + expectedReward);

        uint256 rewardBalance = token0.balanceOf(user);
        assertEq(rewardBalance, expectedReward + stakeAmount);

        vm.stopPrank();
    }

    // Test unstaking with auto-compound set to false after two period
    function testUnstakeAutoCompoundFalseAfterTwoPeriod() public {
        vm.startPrank(user);

        vm.expectEmit(true, true, true, false);
        emit Staked(address(user), address(token0), stakeAmount, false);
        stakeTokens.stake(address(token0), stakeAmount, false);

        // Advance time by 730 days
        vm.warp(block.timestamp + 730 days);

        // Calculate the expected reward
        uint256 expectedReward = compoundInterest(stakeAmount, token0APY, 2, false);

        // Verify the staking results before unstaking
        (uint256 amount, uint256 reward,,,) = stakeTokens.stakes(user, address(token0));

        uint256 expectedTotal = stakeAmount + expectedReward;

        console.log("Stake amount", stakeAmount / 10e18);
        console.log("Expected reward", expectedReward / 10e18);
        console.log("Expected total", expectedTotal / 10e18);

        assertEq(amount, stakeAmount);
        assertEq(reward, 0);

        // Unstake the tokens
        vm.expectEmit(true, true, true, false);
        emit UnStaked(address(user), address(token0), stakeAmount);
        stakeTokens.unstake(address(token0));

        // Verify the unstaking results
        uint256 userBalance = token0.balanceOf(user);
        assertEq(userBalance, stakeAmount + expectedReward);

        uint256 rewardBalance = token0.balanceOf(user);
        assertEq(rewardBalance, expectedReward + stakeAmount);

        vm.stopPrank();
    }

    // Test unstaking with auto-compound set to false after three period
    function testUnstakeAutoCompoundFalseAfterThreePeriod() public {
        vm.startPrank(user);

        vm.expectEmit(true, true, true, false);
        emit Staked(address(user), address(token0), stakeAmount, false);
        stakeTokens.stake(address(token0), stakeAmount, false);

        // Advance time by 1095 days
        vm.warp(block.timestamp + 1095 days);

        // Calculate the expected reward
        uint256 expectedReward = compoundInterest(stakeAmount, token0APY, 3, false);

        // Verify the staking results before unstaking
        (uint256 amount, uint256 reward,,,) = stakeTokens.stakes(user, address(token0));

        uint256 expectedTotal = stakeAmount + expectedReward;

        console.log("Stake amount", stakeAmount / 10e18);
        console.log("Expected reward", expectedReward / 10e18);
        console.log("Expected total", expectedTotal / 10e18);

        assertEq(amount, stakeAmount);
        assertEq(reward, 0);

        // Unstake the tokens
        vm.expectEmit(true, true, true, false);
        emit UnStaked(address(user), address(token0), stakeAmount);
        stakeTokens.unstake(address(token0));

        // Verify the unstaking results
        uint256 userBalance = token0.balanceOf(user);
        assertEq(userBalance, stakeAmount + expectedReward);

        uint256 rewardBalance = token0.balanceOf(user);
        assertEq(rewardBalance, expectedReward + stakeAmount);

        vm.stopPrank();
    }

    // Test unstaking with auto-compound set to true after one period
    function testUnstakeAutoCompoundTrueAfterOnePeriod() public {
        vm.startPrank(user);

        vm.expectEmit(true, true, true, false);
        emit Staked(address(user), address(token0), stakeAmount, false);
        stakeTokens.stake(address(token0), stakeAmount, true);

        // Advance time by 365 days to allow for compounding
        vm.warp(block.timestamp + 365 days);

        // Calculate the expected reward using the compound interest formula
        uint256 expectedReward = compoundInterest(stakeAmount, token0APY, 1, true); // Assuming 1 year of compounding, autoCompound true

        // Expected total amount after unstaking includes the principal + compounded reward
        uint256 expectedTotal = stakeAmount + expectedReward;

        console.log("Stake amount", stakeAmount / 10e18);
        console.log("Expected reward", expectedReward / 10e18);
        console.log("Expected total", expectedTotal / 10e18);

        vm.expectEmit(true, true, true, false);
        emit UnStaked(address(user), address(token0), stakeAmount);
        stakeTokens.unstake(address(token0)); // User unstakes, receiving principal + reward

        // Verify the results
        uint256 finalTokenBalance = token0.balanceOf(user);
        assertEq(finalTokenBalance, expectedTotal, "Final balance does not match expected total after compounding");

        vm.stopPrank();
    }

    // Test unstaking with auto-compound set to true after two period
    function testUnstakeAutoCompoundTrueAfterTwoPeriod() public {
        vm.startPrank(user);

        vm.expectEmit(true, true, true, false);
        emit Staked(address(user), address(token0), stakeAmount, false);
        stakeTokens.stake(address(token0), stakeAmount, true);

        // Advance time by 730 days to allow for compounding
        vm.warp(block.timestamp + 730 days);

        // Calculate the expected reward using the compound interest formula
        uint256 expectedReward = compoundInterest(stakeAmount, token0APY, 2, true); // Assuming 2 year of compounding, autoCompound true

        // Expected total amount after unstaking includes the principal + compounded reward
        uint256 expectedTotal = stakeAmount + expectedReward;

        console.log("Stake amount", stakeAmount / 10e18);
        console.log("Expected reward", expectedReward / 10e18);
        console.log("Expected total", expectedTotal / 10e18);

        vm.expectEmit(true, true, true, false);
        emit UnStaked(address(user), address(token0), stakeAmount);
        stakeTokens.unstake(address(token0)); // User unstakes, receiving principal + reward

        // Verify the results
        uint256 finalTokenBalance = token0.balanceOf(user);
        assertEq(finalTokenBalance, expectedTotal, "Final balance does not match expected total after compounding");

        vm.stopPrank();
    }

    // Test unstaking with auto-compound set to true after three period
    function testUnstakeAutoCompoundTrueAfterThreePeriod() public {
        vm.startPrank(user);

        vm.expectEmit(true, true, true, false);
        emit Staked(address(user), address(token0), stakeAmount, false);
        stakeTokens.stake(address(token0), stakeAmount, true);

        // Advance time by 1095 days to allow for compounding
        vm.warp(block.timestamp + 1095 days);

        // Calculate the expected reward using the compound interest formula
        uint256 expectedReward = compoundInterest(stakeAmount, token0APY, 3, true); // Assuming 3 year of compounding, autoCompound true

        // Expected total amount after unstaking includes the principal + compounded reward
        uint256 expectedTotal = stakeAmount + expectedReward;

        console.log("Stake amount", stakeAmount / 10e18);
        console.log("Expected reward", expectedReward / 10e18);
        console.log("Expected total", expectedTotal / 10e18);

        vm.expectEmit(true, true, true, false);
        emit UnStaked(address(user), address(token0), stakeAmount);
        stakeTokens.unstake(address(token0)); // User unstakes, receiving principal + reward

        // Verify the results
        uint256 finalTokenBalance = token0.balanceOf(user);
        assertEq(finalTokenBalance, expectedTotal, "Final balance does not match expected total after compounding");

        vm.stopPrank();
    }

    function testGetApyByTokenAddress() public {
        // Test for a known token
        uint256 expectedToken0Apy = token0APY;
        uint256 apy0 = stakeTokens.getApyByTokenAddress(address(token0));
        assertEq(apy0, expectedToken0Apy, "APY for token0 should match the initialized value");

        uint256 expectedToken1Apy = token1APY;
        uint256 apy1 = stakeTokens.getApyByTokenAddress(address(token1));
        assertEq(apy1, expectedToken1Apy, "APY for token1 should match the initialized value");

        uint256 expectedToken2Apy = token2APY;
        uint256 apy2 = stakeTokens.getApyByTokenAddress(address(token2));
        assertEq(apy2, expectedToken2Apy, "APY for token2 should match the initialized value");

        // Test for an unsupported token (assuming it should return 0)
        address randomTokenAddress = address(new MockERC20("RandomToken", "RTK"));
        uint256 apyRandom = stakeTokens.getApyByTokenAddress(randomTokenAddress);
        assertEq(apyRandom, 0, "APY for an unsupported token should be 0");
    }

    function testConstructorInitialization() public view {
        // Assuming the constructor sets these values
        assertEq(address(stakeTokens.token0()), address(token0));
        assertEq(address(stakeTokens.token1()), address(token1));
        assertEq(address(stakeTokens.token2()), address(token2));
        assertEq(address(stakeTokens.rewardToken()), address(rewardToken));

        // Checking if APYs are set correctly
        assertEq(stakeTokens.getApyByTokenAddress(address(token0)), token0APY);
        assertEq(stakeTokens.getApyByTokenAddress(address(token1)), token1APY);
        assertEq(stakeTokens.getApyByTokenAddress(address(token2)), token2APY);
    }

    /**
     * @dev Calculates compound or simple interest on a principal over a specified number of periods.
     * Compounds interest if `autoCompound` is true, otherwise calculates simple interest.
     *
     * @param principal The initial principal amount.
     * @param rate Annual interest rate as a percentage (e.g., 10 for 10%).
     * @param periods Number of periods for interest accrual, reflecting the frequency of compounding.
     * @param autoCompound Boolean flag to toggle between compound and simple interest.
     *
     * @return The total interest accrued, excluding the original principal.
     */
    function compoundInterest(uint256 principal, uint256 rate, uint256 periods, bool autoCompound)
        internal
        pure
        returns (uint256)
    {
        uint256 originalPrincipal = principal; // Store original principal to calculate interest
        if (autoCompound) {
            for (uint256 i = 0; i < periods; i++) {
                uint256 interest = (principal * rate) / 100;
                principal += interest; // Compound the interest
            }
        } else {
            principal += (principal * rate * periods) / 100; // Calculate simple interest
        }
        return principal - originalPrincipal; // Return only the interest portion
    }
}
