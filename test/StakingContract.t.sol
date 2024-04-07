// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/StakingContract.sol";
import "../src/BasicToken.sol";
import "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";

contract StakingContractTest is Test {
    StakingContract stakingContract;
    BasicToken basicToken;

    address deployer = address(1);
    address staker1 = address(2);
    address staker2 = address(3);
    address staker3 = address(4);
    address staker4 = address(5);
    address staker5 = address(6);

    function setUp() public {
        // Define the addresses of the stakers
        address[] memory stakers = new address[](5);
        stakers[0] = staker1;
        stakers[1] = staker2;
        stakers[2] = staker3;
        stakers[3] = staker4;
        stakers[4] = staker5;

    
        // Deploy the BasicToken contract and mint tokens to the staker
        basicToken = new BasicToken();
        for (uint i = 0; i < stakers.length; i++) {
            basicToken.transfer(stakers[i], 1_000_000 * 1e18);
        }
        
        // Deploy the StakingContract with the BasicToken as the staking/reward token
        uint256 currentTime = block.timestamp;
        stakingContract = new StakingContract(basicToken, 1e18 /* Reward Rate */, currentTime /* Emission start */, 30 days /* Emission Duration */);
        basicToken.transfer(address(stakingContract), 10_000_000 * 1e18);

        // Approve the StakingContract to spend staker's tokens

        // Approve the StakingContract to spend stakers' tokens
        for (uint i = 0; i < stakers.length; i++) {
            vm.prank(stakers[i]);
            basicToken.approve(address(stakingContract), type(uint256).max);
        }

    }

    /// @notice ==== Staker functions below ====
    function testStakeAmount(uint256 _stakeAmount) public {
        // Bound the input to prevent excessively large values
        uint256 stakeAmount = bound(_stakeAmount, 1e18, 200_000e18);

        // Simulate staker1 staking tokens
        vm.startPrank(staker1);
        stakingContract.stake(stakeAmount);

        // Check if the staked amount is correctly recorded
        (uint256 amountStaked,,,) = stakingContract.stakers(staker1);
        assertEq(amountStaked, stakeAmount);

        stakingContract.stake(stakeAmount);
        stakingContract.stake(stakeAmount);
        stakingContract.stake(stakeAmount);
        vm.stopPrank();

        vm.startPrank(staker2);
        stakingContract.stake(stakeAmount);
        stakingContract.stake(stakeAmount*2);
        (uint256 amountStakedStaker2,,,) = stakingContract.stakers(staker2);
        assertEq(amountStakedStaker2, stakeAmount*3);
        
        (uint256 amountStakedNext,,,) = stakingContract.stakers(staker1);
        assertEq(amountStakedNext, stakeAmount*4);

        vm.stopPrank();
    }


    function testStakeAndEarnRewards(uint256 _stakeAmount, uint256 _timeDelay) public {
        uint256 stakeAmount = bound(_stakeAmount, 1e18, 200_000e18);
        uint256 timeDelay = bound(_timeDelay, 2, stakingContract.unstakeTimeLock()*100);

        // User1 stakes 10000 tokens
        vm.startPrank(staker1);
        stakingContract.stake(stakeAmount);

        // Warp 1 week into the future
        vm.warp(block.timestamp + timeDelay);

        // Claim rewards
        stakingContract.claimReward();

        // Check that user1's balance increased due to rewards
        assertTrue(basicToken.balanceOf(staker1) > stakeAmount);
        vm.stopPrank();
    }

    function testStakeEarnRewardBalanceSingle() public {
        // User1 stakes 10000 tokens
        vm.startPrank(staker1);
        stakingContract.stake(100 * 1e18);

        // Warp 1 week into the future
        vm.warp(block.timestamp + 1 days);

        // Claim rewards
        stakingContract.claimReward();

        // Check that user1's balance increased due to rewards
        assertTrue(basicToken.balanceOf(staker1) > 1000 * 1e18);
        vm.stopPrank();
    }

    function testEarnedAndClaimLinearSingleStaker() public {
        uint256 stakeAmount = 1e18; // 1 token, for simplicity, assuming 18 decimal places
        uint256 rewardRate = 1e18; // Reward rate as per your setup
        uint256 stakingDuration = 1 days; // Staking period for test

        // Stake tokens by staker1
        vm.startPrank(staker1);
        stakingContract.stake(stakeAmount);
        vm.stopPrank();

        assertEq(stakingContract.totalStaked(), stakeAmount, "TotalStaked is not equal staked amount.");

        // Simulate passing of time to the end of staking duration
        vm.warp(block.timestamp + stakingDuration);

        // Calculate expected rewards
        uint256 expectedRewards = rewardRate * stakingDuration; // Adjust if necessary for your reward calculation logic
        
        // Verify the earned rewards for staker1
        uint256 actualEarned = stakingContract.earned(staker1);
        assertEq(actualEarned, expectedRewards, "Earned rewards for single staker do not match expected.");

        uint256 initialBalance = basicToken.balanceOf(staker1);
        vm.startPrank(staker1);
        stakingContract.claimReward();
        vm.stopPrank();
        uint256 finalBalance = basicToken.balanceOf(staker1);
        assertEq(finalBalance - initialBalance, expectedRewards, "Claimed rewards do not match expected rewards.");

    }

    function testEarnedAndClaimLinearMultipleStakers() public {
        uint256 stakeAmount = 1e18; // Each staker stakes 1 token
        uint256 rewardRate = 1e18; // Reward rate as per your setup
        uint256 stakingDuration = 1 days; // Staking period for test

        // Stake tokens by multiple stakers
        address[] memory stakers_mul = new address[](4);
        stakers_mul[0] = staker1;
        stakers_mul[1] = staker2;
        stakers_mul[2] = staker3;
        stakers_mul[3] = staker4;
        
        for (uint256 i = 0; i < stakers_mul.length; i++) {
            vm.startPrank(stakers_mul[i]);
            stakingContract.stake(stakeAmount);
            vm.stopPrank();
        }

        // Simulate passing of time to the end of staking duration
        vm.warp(block.timestamp + stakingDuration);

        // Calculate expected rewards for each staker (assuming equal distribution for simplicity)
        // unused: uint256 totalStake = stakeAmount * stakers_mul.length;
        uint256 totalRewards = rewardRate * stakingDuration; // Adjust based on your reward logic
        uint256 expectedRewardsPerStaker = totalRewards / stakers_mul.length;

        // Verify the earned rewards for each staker
        for (uint256 i = 0; i < stakers_mul.length; i++) {
            vm.prank(stakers_mul[i]);
            uint256 actualEarned = stakingContract.earned(stakers_mul[i]);
            assertEq(actualEarned, expectedRewardsPerStaker, "Earned rewards for staker do not match expected.");
        
            uint256 initialBalance = basicToken.balanceOf(stakers_mul[i]);
            vm.prank(stakers_mul[i]);
            stakingContract.claimReward();
            uint256 finalBalance = basicToken.balanceOf(stakers_mul[i]);
            assertEq(finalBalance - initialBalance, expectedRewardsPerStaker, "Claimed rewards do not match expected rewards.");
        }
        vm.warp(block.timestamp + stakingDuration);
        for (uint256 i = 0; i < stakers_mul.length; i++) {
            vm.prank(stakers_mul[i]);
            uint256 actualEarned = stakingContract.earned(stakers_mul[i]);
            assertEq(actualEarned, expectedRewardsPerStaker, "Earned rewards for staker do not match expected.");
        
            uint256 initialBalance = basicToken.balanceOf(stakers_mul[i]);
            vm.prank(stakers_mul[i]);
            stakingContract.claimReward();
            uint256 finalBalance = basicToken.balanceOf(stakers_mul[i]);
            assertEq(finalBalance - initialBalance, expectedRewardsPerStaker, "Claimed rewards do not match expected rewards.");
        }

        // Staker5 starts staking now
        vm.startPrank(staker5);
        stakingContract.stake(stakeAmount);
        vm.stopPrank();
        // Warp time by another stakingDuration
        vm.warp(block.timestamp + stakingDuration);

        // Now, total rewards need to be calculated for 5 stakers_mul over the second day
        expectedRewardsPerStaker = totalRewards / (stakers_mul.length + 1); // Now dividing by 5 because staker5 is also staking

        // Verifying the rewards for each of the initial stakers_mul (who now have no additional rewards since they claimed)
        for (uint256 i = 0; i < stakers_mul.length; i++) {
            uint256 initialBalance = basicToken.balanceOf(stakers_mul[i]);
            vm.prank(stakers_mul[i]);
            stakingContract.claimReward();
            uint256 finalBalance = basicToken.balanceOf(stakers_mul[i]);
            assertEq(finalBalance - initialBalance, expectedRewardsPerStaker, "Claimed rewards do not match expected rewards.");
        }
        
        uint initialBalance__ = basicToken.balanceOf(staker5);
        vm.prank(staker5);
        stakingContract.claimReward();
        uint finalBalance__ = basicToken.balanceOf(staker5);
        assertEq(finalBalance__ - initialBalance__, expectedRewardsPerStaker, "Claimed rewards do not match expected rewards.");


    }

    function testUnstakeStopsRewardsAccumulation() public {
        uint256 stakeAmount = 1e18; // 1 token, for simplicity, assuming 18 decimal places
        //uint256 rewardRate = 1e18; // Reward rate as per your setup
        uint256 stakingDuration = 1 days; // Staking period for the test
        uint256 unstakingDuration = 1 days; // Duration after initiating unstake

        // Stake tokens by staker1
        console.log("Stake 1eth =0.0=");
        vm.startPrank(staker1);
        stakingContract.stake(stakeAmount);
        vm.stopPrank();

        // Assert initial staked amount
        assertEq(stakingContract.totalStaked(), stakeAmount, "Initial totalStaked is not equal to the staked amount.");

        // Simulate passing of time to the end of staking duration
        vm.warp(block.timestamp + stakingDuration);

        // Initiate unstake
        vm.startPrank(staker1);
        stakingContract.initiateUnstake();
        vm.stopPrank();

        // Calculate expected rewards at the point of unstaking
        //uint256 expectedRewardsAtUnstake = rewardRate * stakingDuration; // Adjust if necessary for your reward calculation logic
        console.log("claimReward #1:");
        vm.startPrank(staker1);
        stakingContract.claimReward();
        vm.stopPrank();

        uint256 initialBalance = basicToken.balanceOf(staker1);
        vm.warp(block.timestamp + unstakingDuration);
        
        console.log("claimReward #2:");
        vm.startPrank(staker1);
        vm.expectRevert("No rewards to claim");
        stakingContract.claimReward();
        vm.stopPrank();

        uint256 finalBalance = basicToken.balanceOf(staker1);
        assertEq(finalBalance - initialBalance, 0, "Claimed rewards after unstaking do not match expected rewards at the point of unstaking.");
    }


function testCompleteUnstakeWithEmissionsFeesWithdraw() public {
        uint256 stakeAmountUser1 = 1e18; // 1 token for user 1
        uint256 stakeAmountUser2 = 3e18; // 2 tokens for user 2
        uint256 stakeAmountUser3 = 1e18; // 1 token for user 3
        uint256 unstakingFeePercentage = 200; // 2% unstaking fee
        uint256 unstakingDelay = 15 days; // Unstaking delay
        uint256 feeAmounts;
        // Set unstaking fee and emission rate
        //vm.startPrank(deployer);
        stakingContract.setUnstakeFeePercent(unstakingFeePercentage);
        //stakingContract.setEmissionDetails(emissionRate, unstakingDelay);
        //vm.stopPrank();

        // User 1 stakes
        vm.startPrank(staker1);
        stakingContract.stake(stakeAmountUser1);
        vm.warp(block.timestamp + 1);
        stakingContract.initiateUnstake();
        vm.stopPrank();

        // User 2 stakes
        vm.startPrank(staker2);
        stakingContract.stake(stakeAmountUser2);
        vm.warp(block.timestamp + 1);
        stakingContract.initiateUnstake();
        vm.stopPrank();

        // User 3 stakes
        vm.startPrank(staker3);
        stakingContract.stake(stakeAmountUser3);
        vm.warp(block.timestamp + 1);
        stakingContract.initiateUnstake();
        vm.stopPrank();


        // Fast forward to after the unstaking delay
        vm.warp(block.timestamp + unstakingDelay);

        vm.startPrank(staker3);
        stakingContract.earned(staker3);
        stakingContract.claimReward();
        vm.stopPrank();

        // Calculate expected returns and fees for both users, incorporating emission effects
        // Assuming rewards are linearly accumulated over time for simplicity
        uint256 feeAmountUser1 = ((stakeAmountUser1 * unstakingFeePercentage) / 10_000);
        

        uint256 feeAmountUser2 = ((stakeAmountUser2 * unstakingFeePercentage) / 10_000);
 
        uint256 totalAmountUser3 = stakeAmountUser3;
        uint256 expectedFeeUser3 = totalAmountUser3 * unstakingFeePercentage / 10_000;
        feeAmounts = expectedFeeUser3 + feeAmountUser2 + feeAmountUser1; 
        // Complete unstaking for both users and validate balances, including rewards

        vm.startPrank(staker1);
        stakingContract.completeUnstake();
        vm.stopPrank();

        vm.startPrank(staker2);
        stakingContract.completeUnstake();
        vm.stopPrank();

        vm.startPrank(staker3);
        stakingContract.completeUnstake();
        vm.stopPrank();
    
        // Check fees here, with basic deployer test, if the amount is correct/

        vm.expectRevert("Amount exceeds accrued fees");
        stakingContract.withdrawFees(feeAmounts*10);

        uint256 ownerBalanceBefore = basicToken.balanceOf(stakingContract.owner());
        console.log("Owner Balance before",ownerBalanceBefore);
        stakingContract.withdrawFees(feeAmounts);
        uint256 ownerBalanceAfter = basicToken.balanceOf(stakingContract.owner());
        console.log("Owner Balance after",ownerBalanceAfter);
        assertEq(ownerBalanceAfter, ownerBalanceBefore + feeAmounts, "The owner cannot withdraw the correct amount");
}



    function testCompleteUnstakeWithEmissionsSimple() public {
        uint256 stakeAmountUser1 = 1e18; // 1 token for user 1
        uint256 stakeAmountUser2 = 1e18; // 2 tokens for user 2
        uint256 stakeAmountUser3 = 1e18; // 1 token for user 3
        uint256 unstakingFeePercentage = 200; // 2% unstaking fee
        uint256 unstakingDelay = 15 days; // Unstaking delay
        uint256 emissionRate = 1e18; // Example emission rate per day for simplicity

        // Set unstaking fee and emission rate
        //vm.startPrank(deployer);
        stakingContract.setUnstakeFeePercent(unstakingFeePercentage);
        //stakingContract.setEmissionDetails(emissionRate, unstakingDelay);
        //vm.stopPrank();

        // User 1 stakes
        vm.startPrank(staker1);
        stakingContract.stake(stakeAmountUser1);
        vm.warp(block.timestamp + 1);
        stakingContract.initiateUnstake();
        vm.stopPrank();

        // User 2 stakes
        vm.startPrank(staker2);
        stakingContract.stake(stakeAmountUser2);
        vm.warp(block.timestamp + 1);
        stakingContract.initiateUnstake();
        vm.stopPrank();

        // User 3 stakes
        vm.startPrank(staker3);
        stakingContract.stake(stakeAmountUser3);
        vm.warp(block.timestamp + 1);
        stakingContract.initiateUnstake();
        vm.stopPrank();


        // Fast forward to after the unstaking delay
        vm.warp(block.timestamp + unstakingDelay);

        vm.startPrank(staker3);
        stakingContract.earned(staker3);
        stakingContract.claimReward();
        vm.stopPrank();

        // Calculate expected returns and fees for both users, incorporating emission effects
        // Assuming rewards are linearly accumulated over time for simplicity
        uint256 totalRewardsUser1 = emissionRate; 
        uint256 StakeMinusFeeUser1 = stakeAmountUser1 - ((stakeAmountUser1 * unstakingFeePercentage) / 10_000);
        uint256 expectedReturnUser1 = totalRewardsUser1 + StakeMinusFeeUser1;
        

        uint256 totalRewardsUser2 = emissionRate; 
        uint256 StakeMinusFeeUser2 = stakeAmountUser2 - ((stakeAmountUser2 * unstakingFeePercentage) / 10_000);
        uint256 expectedReturnUser2 = totalRewardsUser2 + StakeMinusFeeUser2;
 


        uint256 totalAmountUser3 = stakeAmountUser3;
        uint256 expectedFeeUser3 = totalAmountUser3 * unstakingFeePercentage / 10_000;
        uint256 expectedReturnUser3 = stakeAmountUser3 - expectedFeeUser3;

        // Complete unstaking for both users and validate balances, including rewards
        uint256 initialBalanceUser1 = basicToken.balanceOf(staker1);
        uint256 initialBalanceUser2 = basicToken.balanceOf(staker2);
        uint256 initialBalanceUser3 = basicToken.balanceOf(staker3);

        vm.startPrank(staker1);
        stakingContract.completeUnstake();
        vm.stopPrank();
        uint256 finalBalanceUser1 = basicToken.balanceOf(staker1);
        assertEq(finalBalanceUser1 - initialBalanceUser1, expectedReturnUser1, "User 1: Incorrect return amount after fees and rewards.");
        //assertEq(finalBalanceUser1 - initialBalanceUser1, finalBalanceUser1 - initialBalanceUser1, "User 1: Incorrect return amount after fees and rewards.");

        vm.startPrank(staker2);
        stakingContract.completeUnstake();
        vm.stopPrank();
        uint256 finalBalanceUser2 = basicToken.balanceOf(staker2);
        assertEq(finalBalanceUser2 - initialBalanceUser2, expectedReturnUser2, "User 2: Incorrect return amount after fees and rewards.");

        vm.startPrank(staker3);
        stakingContract.completeUnstake();
        vm.stopPrank();
        uint256 finalBalanceUser3 = basicToken.balanceOf(staker3);
        assertEq(finalBalanceUser3 - initialBalanceUser3, expectedReturnUser3, "User 3: Incorrect return amount after fees and rewards.");
    }



    /// @notice Test to measure the correct date of unstakes
    function testUnstakeWithTimelockDateCheck() public {
        vm.startPrank(staker1);
        stakingContract.stake(1 * 1e18);
        // Should fail, Cannot completeUnstake without initialUnstake first
        vm.expectRevert("Unstake not initiated");
        stakingContract.completeUnstake();
        
        // @dev single user linear unstake tests
        stakingContract.stake(100 * 1e18);

        // Initiate unstake
        stakingContract.initiateUnstake();
        (,,,uint256 unstakeInitTime) = stakingContract.stakers(staker1);
        assertEq(unstakeInitTime, block.timestamp);
 
        // Fail: early unstake attempt 
        vm.expectRevert("Timelock not yet passed");
        stakingContract.completeUnstake();

        vm.expectRevert("Unstake already initiated");
        stakingContract.initiateUnstake();
        vm.expectRevert("Timelock not yet passed");
        stakingContract.completeUnstake();

        // Fail: early unstake attempt 
        vm.warp(block.timestamp + 1 days);
        vm.expectRevert("Timelock not yet passed");
        stakingContract.completeUnstake();
        
        // Fail: early unstake attempt 
        vm.warp(block.timestamp + 5 days);
        vm.expectRevert("Timelock not yet passed");
        stakingContract.completeUnstake();
        vm.stopPrank();
        
        vm.startPrank(staker2);
        stakingContract.stake(100 * 1e18);
        stakingContract.initiateUnstake();
        vm.expectRevert("Timelock not yet passed");
        stakingContract.completeUnstake();
        vm.stopPrank();
       
        vm.startPrank(staker3);
        stakingContract.stake(100 * 1e18);
        stakingContract.initiateUnstake();
        vm.expectRevert("Timelock not yet passed");
        stakingContract.completeUnstake();


        vm.stopPrank();


        vm.warp(block.timestamp + 1 days);

        vm.startPrank(staker2);
        vm.expectRevert("Timelock not yet passed");
        stakingContract.completeUnstake();
        vm.stopPrank();
        vm.startPrank(staker3);
        vm.expectRevert("Timelock not yet passed");
        stakingContract.completeUnstake();
        vm.stopPrank();


        vm.startPrank(staker1);
        // Success: unstake after waiting
        vm.warp(block.timestamp + stakingContract.getRemainingUnstakeTime(staker1));
        stakingContract.completeUnstake();
        vm.stopPrank();
        vm.startPrank(staker2);
        vm.expectRevert("Timelock not yet passed");
        stakingContract.completeUnstake();
        vm.stopPrank();
        vm.startPrank(staker3);
        vm.expectRevert("Timelock not yet passed");
        stakingContract.completeUnstake();
        vm.stopPrank();

        vm.warp(block.timestamp + stakingContract.getRemainingUnstakeTime(staker3));
        vm.startPrank(staker2);
        stakingContract.completeUnstake();
        vm.stopPrank();
        vm.startPrank(staker3);
        (,,,uint256 unstakeInitTimePretUnstakeStaker3) = stakingContract.stakers(staker3);
        assertGe(unstakeInitTimePretUnstakeStaker3, 0);
        stakingContract.completeUnstake();
        (,,,uint256 unstakeInitTimePostUnstakeStaker3) = stakingContract.stakers(staker3);
        assertEq(unstakeInitTimePostUnstakeStaker3, 0);

        // @dev Unstake and change unstake time from dev:
        vm.stopPrank();
    }

    /// @notice Test check if unstaking and restaking is possible
    function testEarnedNoAccumulationAfterNoRemainingTime() public {
        vm.startPrank(staker1);

        // stake 1
        stakingContract.stake(1 * 1e18);
        stakingContract.initiateUnstake();
        vm.warp(block.timestamp + stakingContract.getRemainingUnstakeTime(staker1));
        uint256 earnedAfterUnstakeTime = stakingContract.earned(staker1);
        vm.warp(block.timestamp + 15 days);
        uint256 earnedAfterUnstakeTimePlus15days = stakingContract.earned(staker1);
        
        assertEq(earnedAfterUnstakeTime, earnedAfterUnstakeTimePlus15days, "Rewards accumulating if they have not been claimed");
        stakingContract.completeUnstake();

        vm.warp(stakingContract.emissionEnd() - 10);
        vm.stopPrank();
        vm.startPrank(staker2);
        stakingContract.stake(1 * 1e18);
        vm.warp(block.timestamp + 10);
        uint256 currentEarningsStaker2 = stakingContract.earned(staker2);
        vm.warp(block.timestamp + 100 days);
        uint256 laterEarningsStaker2 = stakingContract.earned(staker2);
        assertEq(currentEarningsStaker2, laterEarningsStaker2, "Earnings not equal post Emission end");
        vm.stopPrank();
    }


    /// @notice Test check if unstaking and restaking is possible
    function testUnstakeAndRestake() public {
        vm.startPrank(staker1);
        uint256 balanceBefore = basicToken.balanceOf(staker1);
        // stake 1
        stakingContract.stake(1 * 1e18);
        vm.warp(block.timestamp + 1);

        stakingContract.initiateUnstake();
        vm.warp(block.timestamp + stakingContract.getRemainingUnstakeTime(staker1));
        stakingContract.completeUnstake();


        // stake 2
        stakingContract.stake(1 * 1e18);
        vm.warp(block.timestamp + 1);
        stakingContract.initiateUnstake();
        
        vm.stopPrank();
        vm.startPrank(staker2);
        stakingContract.stake(1 * 1e18);
        vm.warp(block.timestamp + 1);
        stakingContract.initiateUnstake();
        vm.stopPrank();
        vm.startPrank(staker1);
        vm.warp(block.timestamp + stakingContract.getRemainingUnstakeTime(staker1));
        stakingContract.completeUnstake();


        // stake 3
        stakingContract.stake(1 * 1e18);
        vm.warp(block.timestamp + 1);
        stakingContract.initiateUnstake();
        vm.warp(block.timestamp + stakingContract.getRemainingUnstakeTime(staker1));
        stakingContract.completeUnstake();
        vm.stopPrank();
        vm.startPrank(staker2);
        stakingContract.completeUnstake();
        uint256 balanceAfter = basicToken.balanceOf(staker1);

        assertGt(balanceAfter, balanceBefore, "balanceAfter staking and completing 3 times is not greater than balanceBefore");
        vm.stopPrank();

    }


    /// @notice Test to measure the correct balance after `completeUnstake()`
    function testUnstakeWithTimelockBalanceCheck() public {
    }




    /// @notice ===== Admin functions below =====
    /// @notice Test admin change Fees
    function testAdminChangeUnstakeFees() public {
        //vm.startPrank(deployer);
        stakingContract.setUnstakeFeePercent(100); 
        assertEq(stakingContract.unstakeFeePercent(), 100, "Fee not updated correctly to 1%.");
        
        stakingContract.setUnstakeFeePercent(1);
        assertEq(stakingContract.unstakeFeePercent(), 1, "Fee not updated correctly to 0,01%.");
        
        stakingContract.setUnstakeFeePercent(0);
        assertEq(stakingContract.unstakeFeePercent(), 0, "Fee not updated correctly to 2%.");

        stakingContract.setUnstakeFeePercent(200); 
        assertEq(stakingContract.unstakeFeePercent(), 200, "Fee not updated correctly to 2%.");
          
        // Fail; Value too high
        vm.expectRevert("Unstake fee exceeds 2%, maximum allowed");
        stakingContract.setUnstakeFeePercent(600);

        // Check if it reverts on non-owner calls.
        vm.startPrank(staker1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, staker1));
        stakingContract.setUnstakeFeePercent(100); 
        vm.stopPrank();
    }

    function testAdminChangeTimelockDate() public {
        //vm.startPrank(deployer);
        stakingContract.setUnstakeTimeLock(2 days);
        assertEq(stakingContract.unstakeTimeLock(), 2 days, "Timelock end time not updated correctly.");
        stakingContract.setUnstakeTimeLock(5 days);
        assertEq(stakingContract.unstakeTimeLock(), 5 days, "Timelock end time not updated correctly.");
        stakingContract.setUnstakeTimeLock(15 days);
        assertEq(stakingContract.unstakeTimeLock(), 15 days, "Timelock end time not updated correctly.");
        vm.expectRevert("Time lock must be between 0 to 15 days");
        stakingContract.setUnstakeTimeLock(20 days);
        //vm.stopPrank();

        // Check if it reverts on non owner calls.
        vm.startPrank(staker1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector,staker1));
        stakingContract.setUnstakeTimeLock(1 days);
        vm.stopPrank();
    }

    function test_complete_unstake() public {
        vm.prank(staker1);
        stakingContract.stake(400e18);

        vm.prank(staker2);
        stakingContract.stake(500e18);

        vm.expectRevert("Cannot withdraw before emission end");
        stakingContract.withdrawRemainingTokens();

        skip(stakingContract.emissionEnd()/2);

        uint256 prevBalance = basicToken.balanceOf(staker1);
        vm.prank(staker1);
        stakingContract.claimReward();
        assertGt(basicToken.balanceOf(staker1), prevBalance, "staker[0] balance should be greater than previous balance");

        prevBalance = basicToken.balanceOf(staker2);
        vm.prank(staker2);
        stakingContract.claimReward();
        assertGt(basicToken.balanceOf(staker2), prevBalance, "staker[1] balance should be greater than previous balance");

        skip(stakingContract.emissionEnd()/2);

        vm.prank(staker1);
        stakingContract.initiateUnstake();

        vm.prank(staker2);
        stakingContract.initiateUnstake();

        skip(stakingContract.unstakeTimeLock());

        vm.prank(staker1);
        stakingContract.completeUnstake();

        vm.prank(staker2);
        stakingContract.completeUnstake();

        assertGt(basicToken.balanceOf(staker1), 400e18, "staker[0] balance should be 400e18");
        assertGt(basicToken.balanceOf(staker2), 500e18, "staker[1] balance should be 500e18");

        stakingContract.withdrawFees(stakingContract.feesAccrued());

        stakingContract.withdrawRemainingTokens();

        // 100 as there may be some rounding error
        assertLt(basicToken.balanceOf(address(stakingContract)), 100);

        // increase balance and withdraw again
        deal(address(basicToken), address(stakingContract), 1000e18);
        stakingContract.withdrawRemainingTokens();
        assertLt(basicToken.balanceOf(address(stakingContract)), 100);
    }

    function test_notEnoughRewardsToken() public {
        deal(address(basicToken), address(stakingContract), 1000e18);
        deal(address(basicToken), staker1, 400e18);
        deal(address(basicToken), staker2, 500e18);

        vm.prank(staker1);
        stakingContract.stake(400e18);

        vm.prank(staker2);
        stakingContract.stake(500e18);

        skip(stakingContract.emissionEnd()/2);

        vm.prank(staker1);
        vm.expectRevert("Insufficient funds for reward");
        stakingContract.claimReward();

        vm.prank(staker2);
        vm.expectRevert("Insufficient funds for reward");
        stakingContract.claimReward();

        vm.prank(staker1);
        stakingContract.initiateUnstake();

        skip(stakingContract.unstakeTimeLock());

        vm.prank(staker1);
        stakingContract.completeUnstake();
        assertEq(basicToken.balanceOf(staker1), 400e18, "staker[0] should have 400e18");

        skip(stakingContract.emissionEnd()/2);

        vm.prank(staker2);
        stakingContract.initiateUnstake();

        skip(stakingContract.unstakeTimeLock());

        vm.prank(staker1);
        vm.expectRevert("Insufficient funds for reward");
        stakingContract.claimReward();

        vm.prank(staker2);
        vm.expectRevert("Insufficient funds for reward");
        stakingContract.claimReward();

        vm.prank(staker2);
        stakingContract.completeUnstake();
        assertEq(basicToken.balanceOf(staker2), 500e18, "staker[0] should have 400e18");

        vm.prank(staker1);
        vm.expectRevert("Insufficient funds for reward");
        stakingContract.claimReward();

        vm.prank(staker2);
        vm.expectRevert("Insufficient funds for reward");
        stakingContract.claimReward();

        stakingContract.withdrawFees(stakingContract.feesAccrued());

        vm.prank(staker1);
        vm.expectRevert("Insufficient funds for reward");
        stakingContract.claimReward();

        vm.prank(staker2);
        vm.expectRevert("Insufficient funds for reward");
        stakingContract.claimReward();

        // not enough tokens
        vm.expectRevert("No remaining tokens to withdraw");
        stakingContract.withdrawRemainingTokens();

        // increase balance and withdraw again
        deal(address(basicToken), address(stakingContract), 10_000_000 * 1e18);

        vm.prank(staker1);
        stakingContract.claimReward();
        assertGt(basicToken.balanceOf(staker1), 400e18, "staker[0] should have more than 400e18");

        vm.prank(staker2);
        stakingContract.claimReward();
        assertGt(basicToken.balanceOf(staker2), 500e18, "staker[1] should have more than 500e18");

        stakingContract.withdrawRemainingTokens();
        assertLt(basicToken.balanceOf(address(stakingContract)), 100);

        vm.expectRevert("No remaining tokens to withdraw");
        stakingContract.withdrawRemainingTokens();        
    }

    function test_canStakeAfterUnstaking_rewardsMatch() public {
        stakingContract.setUnstakeFeePercent(200);
        deal(address(basicToken), address(stakingContract), 0);
        deal(address(basicToken), staker1, 400e18);

        vm.prank(staker1);
        stakingContract.stake(400e18);   

        skip(stakingContract.emissionEnd()/4);

        vm.prank(staker1);
        stakingContract.initiateUnstake();

        skip(stakingContract.unstakeTimeLock());

        vm.prank(staker1);
        stakingContract.completeUnstake();
        assertEq(basicToken.balanceOf(staker1), 392e18, "staker[0] should have 400e18 - fees");
        (,,uint256 rewards,) = stakingContract.stakers(staker1);
        assertGt(rewards, 0, "staker[0] should have pending rewards");

        vm.prank(staker1);
        stakingContract.stake(392e18);

        skip(stakingContract.emissionEnd()/4);

        vm.prank(staker1);
        stakingContract.initiateUnstake();

        skip(stakingContract.unstakeTimeLock());

        vm.prank(staker1);
        stakingContract.completeUnstake();

        (,,uint256 newRewards,) = stakingContract.stakers(staker1);

        console.log(stakingContract.pendingRewards());
        console.log(newRewards);

        assertEq(basicToken.balanceOf(staker1), 392e18 - 392e18*200/10000, "staker[0] should have 400e18 - fees");

        deal(address(basicToken), address(stakingContract), 10_000_000 * 1e18);

        vm.prank(staker1);
        stakingContract.claimReward();

        assertGt(basicToken.balanceOf(staker1), 392e18 - 392e18*200/10000 + rewards, "staker[0] should have more than 400e18 -fees + rewards");

        skip(stakingContract.emissionEnd() + 1 days - block.timestamp);

        stakingContract.withdrawFees(stakingContract.feesAccrued());

        stakingContract.withdrawRemainingTokens();
        assertLt(basicToken.balanceOf(address(stakingContract)), 100);
    }

    function testStakeAndEarnRewards_NoTokensStuckInContract(uint256 _stakeAmount, uint256 _timeDelay) public {
        uint256 stakeAmount = bound(_stakeAmount, 1e18, 200_000e18);
        uint256 timeDelay = bound(_timeDelay, 6, 30 days);

        // User1 stakes 10000 tokens
        vm.prank(staker1);
        stakingContract.stake(stakeAmount/2);

        // Warp 1 week into the future
        skip(timeDelay / 3);
        
        vm.prank(staker2);
        stakingContract.stake(stakeAmount/2);

        // Check that user1's balance increased due to rewards
        assertTrue(basicToken.balanceOf(staker1) > stakeAmount);

        // Warp 1 week into the future
        skip(2*timeDelay / 3);

        // Claim rewards
        vm.prank(staker1);
        stakingContract.claimReward();
        
        // Check that user1's balance increased due to rewards
        assertTrue(basicToken.balanceOf(staker1) > stakeAmount);

        skip(stakingContract.emissionEnd());

        vm.prank(staker1);
        stakingContract.initiateUnstake();

        vm.prank(staker2);
        stakingContract.initiateUnstake();

        skip(stakingContract.unstakeTimeLock());

        vm.prank(staker1);
        stakingContract.completeUnstake();

        vm.prank(staker2);
        stakingContract.completeUnstake();

        stakingContract.withdrawFees(stakingContract.feesAccrued());
        
        stakingContract.withdrawRemainingTokens();
        assertLt(basicToken.balanceOf(address(stakingContract)), 3);
    }

    function testStakeAndEarnRewards_2stakers(uint256 _stakeAmount, uint256 _timeDelay) public {
            uint256 stakeAmount = bound(_stakeAmount, 1e18, 200_000e18);
            uint256 timeDelay = bound(_timeDelay, 6, 30 days);


            // User1 stakes 10000 tokens
            vm.prank(staker1);
            stakingContract.stake(stakeAmount/2);

            // Warp 1 week into the future
            skip(timeDelay / 3);

            
            vm.prank(staker2);
            stakingContract.stake(stakeAmount/2);

            // Warp 1 week into the future
            skip(2*timeDelay / 3);


            // Claim rewards
            vm.prank(staker1);
            stakingContract.claimReward();
            
            // Check that user1's balance increased due to rewards
            assertTrue(basicToken.balanceOf(staker1) > stakeAmount);

            skip(stakingContract.emissionEnd());
            vm.prank(staker1);
            stakingContract.initiateUnstake();

            vm.prank(staker2);
            stakingContract.initiateUnstake();

            skip(stakingContract.unstakeTimeLock());

            vm.prank(staker1);
            stakingContract.completeUnstake();

            vm.prank(staker2);
            stakingContract.completeUnstake();

            stakingContract.withdrawFees(stakingContract.feesAccrued());
            
            stakingContract.withdrawRemainingTokens();
            assertLt(basicToken.balanceOf(address(stakingContract)), 3);
        }
}
