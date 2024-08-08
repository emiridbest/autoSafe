// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@chainlink/lib/chainlink-brownie-contracts/contracts/src/v0.8/automation/interfaces/AutomationCompatibleInterface.sol";
import "@pythnetwork/IPyth.sol";
import "@pythnetwork/PythStructs.sol";

 contract AutoSafe is ERC20, ReentrancyGuard, AutomationCompatibleInterface {
    struct TokenBalance {
        uint256 celoBalance;
        uint256 cUsdBalance;
        uint256 depositTime;
        uint256 tokenIncentive;
    }

    mapping(address => TokenBalance) public balances;
    mapping(address => address) public upliners;
    mapping(address => address[]) public downliners;
    uint256 public lockDuration = 1 minutes; // for testing
    address public constant CELO_TOKEN_ADDRESS = address(0);
    address public constant CUSD_TOKEN_ADDRESS =
        0x765DE816845861e75A25fCA122bb6898B8B1282a; // 0x765DE816845861e75A25fCA122bb6898B8B1282a
    bool public due = false;

    uint256 public interval;
    uint256 public lastTimeStamp;

    IPyth public pyth;
  bytes32 celoPriceId;
    constructor(address _pyth, bytes32 _celoPriceId) ERC20("miniSafeToken", "MST") {
        _mint(address(this), 21000000 * 1e18);
        interval = 1 minutes;
        lastTimeStamp = block.timestamp;
        pyth = IPyth(_pyth); //(0x74f09cb3c7e2A01865f424FD14F6dc9A14E3e94E); // mainnet 0xff1a0f4744e8582DF1aE09D5611b887B6a12925C
        celoPriceId = _celoPriceId; //0x7d669ddcdd23d9ef1fa9a9cc022ba055ec900e91c4cb960f3c20429d4447a411;
    }

    event Deposited(
        address indexed depositor,
        uint256 amount,
        address indexed token
    );
    event Withdrawn(
        address indexed withdrawer,
        uint256 amount,
        address indexed token
    );
    event TimelockBroken(address indexed breaker, uint256 totalSavings);
    event UplinerSet(address indexed user, address indexed upliner);
    event RewardDistributed(
        address indexed upliner,
        address indexed depositor,
        uint256 amount
    );

    receive() external payable {
        depositCELO(msg.value);
    }

    function setUpliner(address upliner) public {
        require(upliner != address(0), "Upliner cannot be the zero address");
        require(
            upliner != msg.sender,
            "You cannot set yourself as your upliner"
        );
        require(upliners[msg.sender] == address(0), "Upliner already set");
        upliners[msg.sender] = upliner;
        downliners[upliner].push(msg.sender);
        emit UplinerSet(msg.sender, upliner);
    }

    function getDownliners(
        address upliner
    ) public view returns (address[] memory) {
        return downliners[upliner];
    }
        function depositCUSD(uint256 amount) public nonReentrant {
        IERC20 cUsdToken = IERC20(CUSD_TOKEN_ADDRESS);
        require(cUsdToken.transferFrom(msg.sender, address(this), amount), "Transfer failed.");
        TokenBalance storage cUsdBalance = balances[msg.sender];
        cUsdBalance.cUsdBalance += amount;
        cUsdBalance.depositTime = block.timestamp;
        emit Deposited(msg.sender, amount, CUSD_TOKEN_ADDRESS);

        _mint(msg.sender, 1);
        TokenBalance storage tokenIncentive = balances[msg.sender];
        tokenIncentive.tokenIncentive += 1;

        distributeReferralReward(msg.sender, 1);
    }


    /**
      function deposit(address tokenAddress, uint256 amount) public nonReentrant payable {
        if (tokenAddress == CELO_TOKEN_ADDRESS) {
        int256 priceChange = getPriceChange();
        if (priceChange <= -1) {
            require(amount > 0, "CELO deposit amount must be greater than 0");
            TokenBalance storage celoBalance = balances[msg.sender];
            celoBalance.celoBalance += amount;
            celoBalance.depositTime = block.timestamp;
            celoBalance.tokenIncentive = balanceOf(msg.sender);
            emit Deposited(msg.sender, amount, CELO_TOKEN_ADDRESS);
        } else if (tokenAddress == CUSD_TOKEN_ADDRESS) {
            IERC20 cUsdToken = IERC20(CUSD_TOKEN_ADDRESS);
            require(
                cUsdToken.transferFrom(msg.sender, address(this), amount),
                "Transfer failed. Make sure to approve the contract to spend the cUSD tokens."
            );
            TokenBalance storage cUsdBalance = balances[msg.sender];
            cUsdBalance.cUsdBalance += amount;
            cUsdBalance.depositTime = block.timestamp;
            emit Deposited(msg.sender, amount, CUSD_TOKEN_ADDRESS);
        } else {
            revert("Unsupported token");
        }
        _mint(msg.sender, 1);
        TokenBalance storage tokenIncentive = balances[msg.sender];
        tokenIncentive.tokenIncentive += 1;

        distributeReferralReward(msg.sender, 1);
    }
      }

    function getPriceChange(bytes[] calldata priceUpdateData) public returns (PythStructs.Price memory) {
        uint fee = pyth.getUpdateFee(priceUpdateData);
        pyth.updatePriceFeeds{value: fee}(priceUpdateData);

        bytes32 priceId = 0x7d669ddcdd23d9ef1fa9a9cc022ba055ec900e91c4cb960f3c20429d4447a411;
        uint256 age = 24 * 60 * 60;
        PythStructs.Price memory oldBasePrice = pyth.getPriceNoOlderThan(priceId, age);
        PythStructs.Price memory currentBasePrice = pyth.getPrice(priceId);
        int256 change = int256(currentBasePrice.price) - int256(oldBasePrice.price);
        uint256 percentageChange = (uint256(change) * 100) / uint256(oldBasePrice.price);

        return currentBasePrice;
    }
    */
    function getPriceChange() public view returns (int256) {
        uint256 age = 24 * 60 * 60;
        PythStructs.Price memory oldBasePrice = pyth.getPriceNoOlderThan(
            celoPriceId,
            age
        );
        PythStructs.Price memory currentBasePrice = pyth.getPrice(celoPriceId);
        int256 change = int256(currentBasePrice.price) -
            int256(oldBasePrice.price);
        int256 percentageChange = (int256(change) * 100) /
            int256(oldBasePrice.price);

        return percentageChange;
    }

    function depositCELO(uint256 amount) public payable nonReentrant {
        int256 priceChange = getPriceChange();
        if (priceChange <= -1) {
            require(amount > 0, "CELO deposit amount must be greater than 0");
            TokenBalance storage celoBalance = balances[msg.sender];
            celoBalance.celoBalance += amount;
            celoBalance.depositTime = block.timestamp;
            celoBalance.tokenIncentive = balanceOf(msg.sender);
            emit Deposited(msg.sender, amount, CELO_TOKEN_ADDRESS);
        }
        _mint(msg.sender, 1);
        TokenBalance storage tokenIncentive = balances[msg.sender];
        tokenIncentive.tokenIncentive += 1;

        distributeReferralReward(msg.sender, 1);
    }

    function distributeReferralReward(
        address depositor,
        uint256 amount
    ) internal {
        address upliner = upliners[depositor];
        if (upliner != address(0)) {
            uint256 uplinerReward = (amount * 10) / 100;
            _mint(upliner, uplinerReward);
            emit RewardDistributed(upliner, depositor, uplinerReward);
        }
    }

    function timeSinceDeposit(address depositor) public view returns (uint256) {
        return block.timestamp - balances[depositor].depositTime;
    }

    function breakTimelock(address tokenAddress) external payable nonReentrant {
        require(
            (balances[msg.sender].celoBalance > 0 ||
                balances[msg.sender].cUsdBalance > 0),
            "No savings to withdraw"
        );

        TokenBalance storage tokenBalance = balances[msg.sender];
        uint256 amount;
        if (timeSinceDeposit(msg.sender) < lockDuration) {
            due = true;
            uint256 tokenIncentive = tokenBalance.tokenIncentive;
            require(
                tokenIncentive >= 1,
                "Insufficient savings to break timelock"
            );

            if (tokenAddress == CELO_TOKEN_ADDRESS) {
                require(due == true, "Cannot withdraw before lock duration");
                amount = tokenBalance.celoBalance;
                tokenBalance.celoBalance = 0;
                (bool success, ) = payable(msg.sender).call{value: amount}("");
                require(success, "CELO transfer failed");
            } else if (tokenAddress == CUSD_TOKEN_ADDRESS) {
                require(due == true, "Cannot withdraw before lock duration");
                amount = tokenBalance.cUsdBalance;
                tokenBalance.cUsdBalance = 0;
                IERC20 cUsdToken = IERC20(CUSD_TOKEN_ADDRESS);
                require(
                    cUsdToken.transfer(msg.sender, amount),
                    "cUSD transfer failed"
                );
            } else {
                revert("Unsupported token");
            }

            transferFrom(msg.sender, address(0), tokenIncentive);
            emit TimelockBroken(msg.sender, 1);
        }
    }

    function withdraw(address tokenAddress) external nonReentrant {
        TokenBalance storage tokenBalance = balances[msg.sender];
        if (
            (tokenBalance.celoBalance > 0 &&
                timeSinceDeposit(msg.sender) >= lockDuration) ||
            (tokenBalance.cUsdBalance > 0 &&
                timeSinceDeposit(msg.sender) >= lockDuration)
        ) {
            due = true;
        } else {
            revert("Cannot withdraw before lock duration");
        }

        uint256 amount;
        if (tokenAddress == CELO_TOKEN_ADDRESS) {
            amount = tokenBalance.celoBalance;
            tokenBalance.celoBalance = 0;
            payable(msg.sender).transfer(amount);
        } else if (tokenAddress == CUSD_TOKEN_ADDRESS) {
            amount = tokenBalance.cUsdBalance;
            tokenBalance.cUsdBalance = 0;
            IERC20 cUsdToken = IERC20(CUSD_TOKEN_ADDRESS);
            require(cUsdToken.transfer(msg.sender, amount), "Transfer failed");
        } else {
            revert("Unsupported token");
        }

        emit Withdrawn(msg.sender, amount, tokenAddress);
    }

    function getBalance(
        address account,
        address tokenAddress
    ) public view returns (uint256) {
        TokenBalance storage tokenBalance = balances[account];
        if (tokenAddress == CELO_TOKEN_ADDRESS) {
            return tokenBalance.celoBalance;
        } else if (tokenAddress == CUSD_TOKEN_ADDRESS) {
            return tokenBalance.cUsdBalance;
        } else {
            revert("Unsupported token");
        }
    }

    function checkUpkeep() external view returns (bool upkeepNeeded) {
        upkeepNeeded = (block.timestamp - lastTimeStamp) > interval;
    }

    function performUpkeep(address tokenAddress, uint256 amount) external {
        if ((block.timestamp - lastTimeStamp) > interval) {
            lastTimeStamp = block.timestamp;
            if (tokenAddress == CUSD_TOKEN_ADDRESS) {
                depositCUSD(amount);
            }
            if (tokenAddress == CELO_TOKEN_ADDRESS) {
                depositCELO(amount);
            }
        }
    }

    /**    function saveFixedAmount() internal {
        uint256 amount = 1 * 1e18; // Example amount to save
        // Implement the logic to save the amount for all users or specific users
        // Example: Transfer tokens from the contract to users or another contract
    } */
    function checkUpkeep(
        bytes calldata checkData
    ) external override returns (bool upkeepNeeded, bytes memory performData) {}

    function performUpkeep(bytes calldata performData) external override {}
}
