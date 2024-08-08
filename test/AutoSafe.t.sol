// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/AutoSafe.sol"; // Adjust the path as necessary
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {MockPyth} from "@pythnetwork/MockPyth.sol";
contract MockToken is ERC20 {
    constructor() ERC20("Mock Token", "MTK") {
        _mint(msg.sender, 1000000 * 1e18);
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

contract AutoSafeTest is Test {
    AutoSafe public autoSafe;
    MockToken public cUsdToken;
    address constant cUsdTokenAddress =
        0x765DE816845861e75A25fCA122bb6898B8B1282a;

    address user1;
    address user2;
    MockPyth public pyth;
    bytes32 CELO_PRICE_FEED_ID = bytes32(uint256(0x1));

    uint256 CELO_TO_WEI = 10 ** 18;

    function setUp() public {
        user1 = address(1);
        user2 = address(2);
        // set up Pyth oracle
        pyth = new MockPyth(60, 1);
        // Deploy a mock cUSD token
        cUsdToken = new MockToken();
        // Assign the mock token to the specific address
        vm.etch(cUsdTokenAddress, address(cUsdToken).code);
        cUsdToken = MockToken(cUsdTokenAddress); // Reassign the address to cUsdToken
        pyth = new MockPyth(60, 1);
        // Deploy the AutoSafe contract
        autoSafe = new AutoSafe(address(pyth), CELO_PRICE_FEED_ID);

        // Transfer some cUSD tokens to users for testing
        cUsdToken.mint(user1, 1000 * 1e18);
        cUsdToken.mint(user2, 1000 * 1e18);

        // Label the addresses for better test output readability
        vm.label(user1, "User1");
        vm.label(user2, "User2");
        vm.label(address(autoSafe), "AutoSafe Contract");
    }
    function createEthUpdate(
        int64 celoPrice
    ) private view returns (bytes[] memory) {
        bytes[] memory updateData = new bytes[](1);
        updateData[0] = pyth.createPriceFeedUpdateData(
            CELO_PRICE_FEED_ID,
            celoPrice * 100000, // price
            10 * 100000, // confidence
            -5, // exponent
            celoPrice * 100000, // emaPrice
            10 * 100000, // emaConfidence
            uint64(block.timestamp) // publishTime
        );

        return updateData;
    }

    function setCeloPrice(int64 celoPrice) private {
        bytes[] memory updateData = createEthUpdate(celoPrice);
        uint value = pyth.getUpdateFee(updateData);
        vm.deal(address(this), value);
        pyth.updatePriceFeeds{value: value}(updateData);
    }
    function testDepositCELO() public {
        setCeloPrice(99);
        uint256 depositAmount = 1 ether;
        vm.deal(user1, depositAmount);
        vm.prank(user1);
        autoSafe.depositCELO(depositAmount);

        uint256 celoBalance;
        uint256 cUsdBalance;
        uint256 depositTime;
        uint256 tokenIncentive;

        // Retrieve values from autoSafe.balances(user1)
        (celoBalance, cUsdBalance, depositTime, tokenIncentive) = autoSafe
            .balances(user1);

        // Create a TokenBalance struct with the retrieved values
        AutoSafe.TokenBalance memory balance = AutoSafe.TokenBalance({
            celoBalance: celoBalance,
            cUsdBalance: cUsdBalance,
            depositTime: depositTime,
            tokenIncentive: tokenIncentive
        });
        console.log(tokenIncentive, celoBalance);
        assertEq(balance.celoBalance, celoBalance);
    }
    function testDepositCUSD() public {
        vm.startPrank(user1);

        uint256 depositAmount = 100 * 1e18;
        cUsdToken.approve(address(autoSafe), depositAmount);

        autoSafe.depositCUSD(depositAmount);
        uint256 celoBalance;
        uint256 cUsdBalance;
        uint256 depositTime;
        uint256 tokenIncentive;
        // Retrieve values from autoSafe.balances(user1)
        (celoBalance, cUsdBalance, depositTime, tokenIncentive) = autoSafe
            .balances(user1);
        // Create a TokenBalance struct with the retrieved values
        AutoSafe.TokenBalance memory balance = AutoSafe.TokenBalance({
            celoBalance: celoBalance,
            cUsdBalance: cUsdBalance,
            depositTime: depositTime,
            tokenIncentive: tokenIncentive
        });
        // Check that the contract has the correct cUSD balance
        assertEq(balance.cUsdBalance, depositAmount);

        // Check that the user's balance in the contract is updated
        //  assertEq(autoSafe.getBalance(user1, address(cUsdToken)), depositAmount);

        vm.stopPrank();
    }

    function testWithdrawCUSD() public {
        vm.startPrank(user1);

        uint256 depositAmount = 100 * 1e18;
        cUsdToken.approve(address(autoSafe), depositAmount);
        autoSafe.depositCUSD(depositAmount);

        // Simulate the passage of time to exceed the lockDuration
        vm.warp(block.timestamp + 1 minutes);

        autoSafe.withdraw(address(cUsdToken));

        // Check that the contract's cUSD balance is zero
        assertEq(cUsdToken.balanceOf(address(autoSafe)), 0);

        // Check that the user received their withdrawn cUSD
        assertEq(cUsdToken.balanceOf(user1), 1000 * 1e18);

        vm.stopPrank();
    }

    function testSetUplinerAndReferralReward() public {
        vm.startPrank(user1);

        autoSafe.setUpliner(user2);

        assertEq(autoSafe.upliners(user1), user2);

        vm.stopPrank();
    }

    function testBreakTimelock() public { //incomplete test
        vm.startPrank(user1);

        uint256 depositAmount = 100 * 1e18;
        cUsdToken.approve(address(autoSafe), depositAmount);
        autoSafe.depositCUSD(depositAmount);

        // Try to break the timelock before the lock duration
        vm.expectRevert("Cannot withdraw before lock duration");
        autoSafe.breakTimelock(address(cUsdToken));

        // Simulate the passage of time to be within the lock duration but try to break the timelock
        vm.warp(block.timestamp + 30 seconds);
        vm.expectRevert("Insufficient savings to break timelock");
        autoSafe.breakTimelock(address(cUsdToken));

        vm.stopPrank();
    }

    function testPerformUpkeep() public {
        vm.startPrank(user1);

        uint256 depositAmount = 100 * 1e18;
        cUsdToken.approve(address(autoSafe), depositAmount);

        // Simulate the passage of time to trigger upkeep
        vm.warp(block.timestamp + 2 minutes);

        // Perform upkeep to deposit cUSD automatically
        autoSafe.performUpkeep(address(cUsdToken), depositAmount);

        // Check that the contract has the correct cUSD balance
        // uint256 celoBalance;
        uint256 celoBalance;
        uint256 cUsdBalance;
        uint256 depositTime;
        uint256 tokenIncentive;
        // Retrieve values from autoSafe.balances(user1)
        (celoBalance, cUsdBalance, depositTime, tokenIncentive) = autoSafe
            .balances(user1);
        // Create a TokenBalance struct with the retrieved values
        AutoSafe.TokenBalance memory balance = AutoSafe.TokenBalance({
            celoBalance: celoBalance,
            cUsdBalance: cUsdBalance,
            depositTime: depositTime,
            tokenIncentive: tokenIncentive
        });
        // Check that the contract has the correct cUSD balance
        assertEq(balance.cUsdBalance, depositAmount);
        vm.stopPrank();
    }
}
