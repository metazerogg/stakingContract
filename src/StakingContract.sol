// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract StakingContract is ReentrancyGuard, Ownable {
    IERC20 public basicToken;

    uint256 public totalStaked;
    uint256 public totalStakedAccruingRewards;  
    uint256 public rewardRate;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;
    uint256 public unstakeTimeLock = 7 days; // Default time lock for unstaking
    uint256 public unstakeFeePercent = 0; // Fee for unstaking, in basis points
    uint256 public emissionStart;
    uint256 public emissionEnd;
    uint256 public feesAccrued;
    uint256 public pendingRewardsStored;
    
    uint256 private constant MAX_FEE = 200;
    uint256 private constant BASIS_POINTS = 10000;
    uint256 private constant MAX_TIMELOCK = 15 days;

    struct Staker {
        uint256 amountStaked;
        uint256 rewardDebt;
        uint256 rewards;
        uint256 unstakeInitTime; 
    }

    mapping(address => Staker) public stakers;

    event UnstakeInitiated(address indexed user);
    event Staked(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event UnstakeFeePercentUpdated(uint256 newFeePercent);
    event UnstakeTimeLockUpdated(uint256 newTimeLock);

    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        pendingRewardsStored = pendingRewards();
        lastUpdateTime = lastApplicableTime();
        Staker storage staker = stakers[account];
        if (staker.unstakeInitTime == 0 ) {
            staker.rewards = earned(account);
            staker.rewardDebt = rewardPerTokenStored;
        }
        
        // else if (staker.unstakeInitTIme !=0)
        //staker.rewards = staker.rewards;
        _;
    }

    constructor(IERC20 _basicToken, uint256 _rewardRate, uint256 _emissionStart, uint256 _emissionDuration) Ownable(msg.sender) {
        basicToken = _basicToken;
        rewardRate = _rewardRate;
        emissionStart = _emissionStart;
        emissionEnd = emissionStart + _emissionDuration;
    }

    function lastApplicableTime() public view returns (uint256) {
        return block.timestamp < emissionEnd ? block.timestamp : emissionEnd;
    }

    function pendingRewards() public view returns (uint256) {
        uint256 totalStakedAccruingRewardsCached = totalStakedAccruingRewards;
        if (totalStakedAccruingRewardsCached == 0) return pendingRewardsStored;
        uint256 fullPendingRewards = (lastApplicableTime() - lastUpdateTime) * rewardRate;
        uint256 realPendingRewards = fullPendingRewards*1e18/totalStakedAccruingRewardsCached*totalStakedAccruingRewardsCached/1e18;
        return pendingRewardsStored + realPendingRewards;
    }
    function rewardPerToken() public view returns (uint256) {
        if (totalStakedAccruingRewards == 0) {
            return rewardPerTokenStored;
        }
        return rewardPerTokenStored + (
            (lastApplicableTime() - lastUpdateTime) * rewardRate * 1e18 / totalStakedAccruingRewards
        );
    }

    function earned(address account) public view returns (uint256) {
        Staker storage staker = stakers[account];
        if (staker.unstakeInitTime != 0) {
                return staker.rewards;
        }
        return (
            staker.amountStaked *
            (rewardPerToken() - staker.rewardDebt) / 1e18
        ) + staker.rewards;
    }


    function stake(uint256 _amount) external nonReentrant updateReward(msg.sender) {
        require(_amount > 0, "Cannot stake 0");
        require(block.timestamp >= emissionStart, "Staking not yet started");
        require(block.timestamp <= emissionEnd, "Staking period has ended");
        Staker storage staker = stakers[msg.sender];
        require(staker.unstakeInitTime == 0, "Cannot stake after initiating unstake.");
        totalStaked += _amount;
        totalStakedAccruingRewards += _amount;
        staker.amountStaked += _amount;
        require(basicToken.transferFrom(msg.sender, address(this), _amount), "Token deposit failed");
        emit Staked(msg.sender, _amount);
    }

    function initiateUnstake() external updateReward(msg.sender) {
        Staker storage staker = stakers[msg.sender];
        require(staker.amountStaked > 0, "No tokens staked");
        require(staker.unstakeInitTime == 0, "Unstake already initiated");
        staker.unstakeInitTime = block.timestamp;
        totalStakedAccruingRewards -= staker.amountStaked;
        emit UnstakeInitiated(msg.sender);
    }

    function completeUnstake() external nonReentrant updateReward(msg.sender) {
        Staker storage staker = stakers[msg.sender];
        require(staker.amountStaked > 0, "No tokens staked");
        require(staker.unstakeInitTime > 0, "Unstake not initiated");
        require(block.timestamp >= staker.unstakeInitTime + unstakeTimeLock, "Timelock not yet passed");

        uint256 amount = staker.amountStaked;
        uint256 reward = staker.rewards;
        uint256 fee = amount * unstakeFeePercent / BASIS_POINTS;
        uint256 amountAfterFee = amount - fee;

        uint256 availableForRewards = _getFreeContractBalance();

        feesAccrued += fee;
        totalStaked -= amount;
        staker.amountStaked = 0;
        staker.rewardDebt = 0;
        staker.unstakeInitTime = 0;

        uint256 totalAmount = amountAfterFee;
        // If there are rewards, combine them with the staked amount after fees for a single transfer
        if (reward > 0 && availableForRewards >= reward) {
            pendingRewardsStored -= reward;
            totalAmount += reward;
            staker.rewards = 0;
            emit RewardPaid(msg.sender, reward);
        }
        require(basicToken.transfer(msg.sender, totalAmount), "Unstake transfer failed");
        emit Unstaked(msg.sender, amount);
    }

    function claimReward() external nonReentrant updateReward(msg.sender) {
        Staker storage staker = stakers[msg.sender];
        uint256 reward = staker.rewards;
        require(reward > 0, "No rewards to claim");

        // Calculate the available balance for rewards
        uint256 availableForRewards = _getFreeContractBalance();
        require(availableForRewards >= reward, "Insufficient funds for reward");

        pendingRewardsStored -= reward;
        staker.rewards = 0;
        require(basicToken.transfer(msg.sender, reward), "Reward transfer failed");
        emit RewardPaid(msg.sender, reward);
    }

    function setUnstakeFeePercent(uint256 _newFee) external onlyOwner {
        require(_newFee <= MAX_FEE, "Unstake fee exceeds 2%, maximum allowed"); 
        unstakeFeePercent = _newFee;
        emit UnstakeFeePercentUpdated(_newFee); 
    }

    function setUnstakeTimeLock(uint256 _newTimeLock) external onlyOwner {
        require(_newTimeLock <= MAX_TIMELOCK, "Time lock must be between 0 to 15 days");
        unstakeTimeLock = _newTimeLock;
        emit UnstakeTimeLockUpdated(_newTimeLock);
    }

    function getRemainingUnstakeTime(address _staker) external view returns (uint256) {
        Staker storage staker = stakers[_staker];
        if (block.timestamp < staker.unstakeInitTime + unstakeTimeLock) {
            return (staker.unstakeInitTime + unstakeTimeLock) - block.timestamp;
        } else {
            return 0;
        }
    }

    function withdrawFees(uint256 amount) external onlyOwner {
        require(amount <= feesAccrued, "Amount exceeds accrued fees");
        feesAccrued -= amount;
        require(basicToken.transfer(msg.sender, amount), "Fee withdrawal failed");
    }

    function withdrawRemainingTokens() external updateReward(address(0)) onlyOwner {
        require(block.timestamp > emissionEnd, "Cannot withdraw before emission end");
        uint256 remainingBalance = _getFreeContractBalance() - pendingRewards();
        require(remainingBalance > 0, "No remaining balance");
        require(basicToken.transfer(msg.sender, remainingBalance), "Token withdrawal failed");
    }


    function _getFreeContractBalance() internal view returns (uint256) {
        return basicToken.balanceOf(address(this)) - totalStaked - feesAccrued;
    }
}
