// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import {StakeLib} from "./libraries/StakeLib.sol";

contract StakeTokens {
    using SafeERC20 for IERC20;

    IERC20 public token0;
    IERC20 public token1;
    IERC20 public token2;
    IERC20 public rewardToken;

    uint256 public token0APY;
    uint256 public token1APY;
    uint256 public token2APY;

    // Mapping from addresses to their respective Annual Percentage Yields (APYs).
    mapping(address => uint256) public tokensAPY;
    // Nested mapping that tracks staking information for each user and token address.
    mapping(address => mapping(address => StakeLib.StakeInformation)) public stakes;

    /// @notice Emitted when a user stakes a token.
    /// @param user Address of the user who staked the token.
    /// @param tokenAddress Address of the staked token.
    /// @param amount Amount of token staked by the user.
    /// @param autoCompound Option to stake rewards automatically.
    event Staked(address indexed user, address tokenAddress, uint256 amount, bool autoCompound);

    /// @notice Emitted when users withdraw their rewards.
    /// @param user Address of the user who withdrew rewards.
    /// @param tokenAddress Address of the token from which rewards are withdrawn.
    /// @param amount Amount of rewards withdrawn by the user.
    event RewardWithdrawn(address indexed user, address tokenAddress, uint256 amount);

    /// @notice Emitted when users unstake their tokens.
    /// @param user Address of the user who unstaked the token.
    /// @param tokenAddress Address of the unstaked token.
    /// @param amount Amount of token unstaked by the user.
    event UnStaked(address indexed user, address tokenAddress, uint256 amount);

    // Constructor to initialize the contract with token addresses and their respective APYs.
    constructor(
        address _token0Address,
        address _token1Address,
        address _token2Address,
        address _rewardToken,
        uint256 _token0APY,
        uint256 _token1APY,
        uint256 _token2APY
    ) {
        token0 = IERC20(_token0Address);
        token1 = IERC20(_token1Address);
        token2 = IERC20(_token2Address);
        rewardToken = IERC20(_rewardToken);

        tokensAPY[_token0Address] = _token0APY;
        tokensAPY[_token1Address] = _token1APY;
        tokensAPY[_token2Address] = _token2APY;
    }

    /// @notice Function to stake a specified amount of a token with an option for auto-compounding rewards.
    /// @param tokenAddress Address of the token the user wants to stake.
    /// @param amount Amount of token the user wants to stake.
    /// @param autoCompound Option to enable auto-compounding of rewards.
    function stake(address tokenAddress, uint256 amount, bool autoCompound) external {
        require(tokensAPY[tokenAddress] > 0, "Token not supported for staking.");

        IERC20 token = IERC20(tokenAddress);
        token.safeTransferFrom(msg.sender, address(this), amount);

        StakeLib.StakeInformation storage userStake = stakes[msg.sender][tokenAddress];
        uint256 reward = StakeLib.calculateReward(userStake);

        if (userStake.autoCompound) {
            userStake.amount += reward; // Compounds the existing reward
            userStake.reward = 0; // Resets the reward since it's added to the principal
        } else {
            userStake.reward += reward;
        }

        userStake.amount += amount; // Add new staked amount
        userStake.startTime = block.timestamp; // Reset the start time on new stakes or updates
        userStake.autoCompound = autoCompound;
        userStake.apy = tokensAPY[tokenAddress];

        emit Staked(msg.sender, tokenAddress, amount, autoCompound);
    }

    /// @notice Function to unstake tokens and withdraw rewards.
    /// @param tokenAddress Address of the token the user wants to unstake.
    function unstake(address tokenAddress) external {
        StakeLib.StakeInformation storage userStake = stakes[msg.sender][tokenAddress];
        require(userStake.amount > 0, "No stake to unstake.");

        uint256 reward = StakeLib.calculateReward(userStake);
        if (userStake.autoCompound) {
            userStake.amount += reward; // Compound the reward before unstaking
        } else {
            userStake.reward += reward;
        }

        uint256 totalAmount = userStake.amount + userStake.reward;
        userStake.amount = 0;
        userStake.reward = 0;
        userStake.startTime = block.timestamp;

        IERC20 token = IERC20(tokenAddress);
        token.safeTransfer(msg.sender, totalAmount);

        emit UnStaked(msg.sender, tokenAddress, totalAmount);
    }

    /// @notice Function to withdraw accumulated rewards.
    /// @param tokenAddress Address of the token from which the user wants to withdraw rewards.
    function withdrawReward(address tokenAddress) external {
        StakeLib.StakeInformation storage userStake = stakes[msg.sender][tokenAddress];
        uint256 reward = StakeLib.calculateReward(userStake);

        if (userStake.autoCompound) {
            userStake.amount += reward; // Automatically compound the reward
            userStake.reward = 0; // Reset the reward since it's compounded
        } else {
            userStake.reward += reward;
            rewardToken.safeTransfer(msg.sender, userStake.reward); // Transfer reward
            userStake.reward = 0; // Reset after withdrawal
        }

        userStake.startTime = block.timestamp; // Reset the time for accurate reward calculation

        emit RewardWithdrawn(msg.sender, tokenAddress, reward);
    }

    /// @notice Function to get the APY for a specific token.
    /// @param tokenAddress Address of the token for which the APY is requested.
    function getApyByTokenAddress(address tokenAddress) public view returns (uint256) {
        return tokensAPY[tokenAddress];
    }
}
