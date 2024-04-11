// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Test, console, Vm} from "forge-std/Test.sol";
import {Lottery} from "../../src/Lottery.sol";
import {DeployLottery} from "../../script/DeployLottery.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {VRFCoordinatorV2Mock} from "@chainlink/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";

contract LotteryTest is Test {
    event Lottery_newPlayer(address indexed player);

    Lottery private lottery;
    HelperConfig private helperConfig;
    address public PLAYER = makeAddr("player");
    uint256 public USER_STARTING_BALANCE = 10 ether;
    uint256 entranceFee;
    uint256 interval;
    address vrfCoordinator;
    bytes32 gasLane;
    uint64 subscriptionId;
    uint32 callbackGasLimit;
    address link;

    function setUp() external {
        DeployLottery deployer = new DeployLottery();
        (lottery, helperConfig) = deployer.run();
        (entranceFee, interval, vrfCoordinator, gasLane, subscriptionId, callbackGasLimit, link) =
            helperConfig.activeNetworkConfig();
        vm.deal(PLAYER, USER_STARTING_BALANCE);
    }

    modifier lotteryStartedAndTimePassed() {
        vm.prank(PLAYER);
        lottery.enterLottery{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        _;
    }

    function testInitializesInOpenState() public view {
        assert(lottery.getLotteryState() == Lottery.LotteryState.OPEN);
    }

    function testEntranceFee() public view {
        // lottery.enterLottery{value: 0.01 ether}();
        assert(lottery.getEntranceFee() == entranceFee);
    }

    function testLotteryRevertWhenYouDontPayEnough() public {
        vm.prank(PLAYER);
        vm.expectRevert(Lottery.Lottery__NotEnoughEthSent.selector);
        lottery.enterLottery();
    }

    function testLotteryPlayerAfterEnter() public {
        vm.prank(PLAYER);
        lottery.enterLottery{value: entranceFee}();
        address playerRecorded = lottery.getPlayer(0);
        assert(playerRecorded == PLAYER);
    }

    function testEmitEventOnEntrance() public {
        vm.prank(PLAYER);
        vm.expectEmit(true, false, true, false, address(lottery));
        emit Lottery_newPlayer(PLAYER);
        lottery.enterLottery{value: entranceFee}();
    }

   
}
