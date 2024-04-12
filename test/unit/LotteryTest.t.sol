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

    function testWhenLotteryIsCalculating() public {
        vm.prank(PLAYER);
        lottery.enterLottery{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        lottery.performUpKeep("");

        vm.expectRevert(Lottery.Lottery__LotteryNotOpen.selector);
        vm.prank(PLAYER);
        lottery.enterLottery{value: entranceFee}();
    }

    function testWhenLotteryDoesNotHaveEnoughBalance() public {
        vm.prank(PLAYER);
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        (bool upKeep,) = lottery.checkUpkeep("");
        assert(upKeep == false);
    }

    function testCheckUpKeepWhenLotteryIsNotOpen() public {
        vm.prank(PLAYER);
        lottery.enterLottery{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        lottery.performUpKeep("");

        (bool upKeep,) = lottery.checkUpkeep("");
        assert(upKeep == false);
    }

    function testWhenEnoughTimeHasntPassed() public {
        vm.prank(PLAYER);
        lottery.enterLottery{value: entranceFee}();
        vm.warp(block.timestamp + interval - 1);
        vm.roll(block.number + 1);

        (bool upKeep,) = lottery.checkUpkeep("");
        assert(upKeep == false);
    }

    function testCheckReturnsTrueWhenAllParametersAreGood() public lotteryStartedAndTimePassed {
        (bool upKeep,) = lottery.checkUpkeep("");
        assert(upKeep == true);
    }

    function testPerformUpKeepCanRunOnlyIfCheckUpKeepIsTrue() public lotteryStartedAndTimePassed {
        lottery.performUpKeep("");
    }

    function testPerformUpKeepRevertIfCheckUpKeepIsFalse() public {
        uint256 currentBalance = 0;
        uint256 numPlayers = 0;
        uint256 lotteryState = 0;
        vm.expectRevert(
            abi.encodeWithSelector(Lottery.Lottery__upKeepNotNeeded.selector, currentBalance, numPlayers, lotteryState)
        );

        lottery.performUpKeep("");
    }

    function testEventDataFromPerformUpKeep() public lotteryStartedAndTimePassed {
        vm.recordLogs();
        lottery.performUpKeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();

        bytes32 emittedRequestId = entries[1].topics[1];
        Lottery.LotteryState lState = lottery.getLotteryState();

        assert(uint256(emittedRequestId) > 0);
        assert(uint256(lState) == 1);
        assert(lState == Lottery.LotteryState.CALCULATING);
    }

    function testFulfillRandomWordsCanOnlyBeCalledAfterPerformUpKeep(uint256 _randomRequestId) public {
        vm.expectRevert("nonexistent request");
        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(_randomRequestId, address(lottery));
    }

    function testFullFillRandomWordsAndPickWinner() public lotteryStartedAndTimePassed {
        uint256 initialPlayers = 1;
        uint256 additionalPlayers = 5;

        for (uint256 i = 1; i < initialPlayers + additionalPlayers; i++) {
            address user = address(uint160(i));
            hoax(user, USER_STARTING_BALANCE); //combination of prank and deal
            lottery.enterLottery{value: entranceFee}();
        }

        vm.recordLogs();
        lottery.performUpKeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 winnerRequestId = entries[1].topics[1];
        console.log("winnerRequestId---", uint256(winnerRequestId));

        uint256 numberOfPlayers = lottery.getNumberOfPlayers();
        uint256 lotteryAmount = USER_STARTING_BALANCE + entranceFee * (additionalPlayers);
        uint256 lastTimeStamp = lottery.getLastTimeStamp();
        console.log("lotteryAmount---", lotteryAmount);

        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(uint256(winnerRequestId), address(lottery));

        assert(numberOfPlayers == (initialPlayers + additionalPlayers));
        assert(lotteryAmount == address(lottery.getWinnerPlayer()).balance);
        assert(lottery.getLotteryState() == Lottery.LotteryState.OPEN);
        assert(lottery.getNumberOfPlayers() == 0);
        assert(lastTimeStamp + interval < lottery.getLastTimeStamp());
    }
}
