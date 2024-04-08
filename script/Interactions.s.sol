// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Script, console} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {VRFCoordinatorV2Mock} from "@chainlink/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";
import {LinkToken} from "../test/mocks/LinkToken.sol";
import {DevOpsTools} from "foundry-devops/src/DevOpsTools.sol";

contract CreateSusbscription is Script {
    function createSusbscriptionUsingConfig() public returns (uint64) {
        HelperConfig helperConfig = new HelperConfig();
        (,, address vrfCoordinator,,,,) = helperConfig.activeNetworkConfig();
        return createSubscription(vrfCoordinator);
    }

    function createSubscription(address _vrfCoordinator) public returns (uint64) {
        vm.startBroadcast();
        uint64 subId = VRFCoordinatorV2Mock(_vrfCoordinator).createSubscription();
        console.log("subId is:", subId);
        vm.stopBroadcast();
        return subId;
    }

    function run() external returns (uint64) {
        return createSusbscriptionUsingConfig();
    }
}

contract FundSubscription is Script {
    uint96 private constant FUND_SUBSCRIPTION_AMOUNT = 3 ether;

    function fundSusbscriptionUsingConfig() public {
        HelperConfig helperConfig = new HelperConfig();
        (,, address vrfCoordinator,, uint64 subId,, address link) = helperConfig.activeNetworkConfig();
        fundSubscription(vrfCoordinator, subId, link);
    }

    function fundSubscription(address _vrfCoordinator, uint64 _subId, address _link) public {
        console.log("vrfCoordinator is:", _vrfCoordinator);
        console.log("subId is:", _subId);
        console.log("link is:", _link);

        if (block.chainid == 31337) {
            vm.startBroadcast();
            VRFCoordinatorV2Mock(_vrfCoordinator).fundSubscription(_subId, FUND_SUBSCRIPTION_AMOUNT);
            vm.stopBroadcast();
        } else {
            vm.startBroadcast();
            LinkToken(_link).transferAndCall(_vrfCoordinator, FUND_SUBSCRIPTION_AMOUNT, abi.encode(_subId));
            vm.stopBroadcast();
        }
    }

    function run() external {
        fundSusbscriptionUsingConfig();
    }
}

contract AddConsumer is Script {
    function addConsumerUsingConfig(address _lottery) public {
        HelperConfig helperConfig = new HelperConfig();
        (,, address vrfCoordinator,,, uint64 subId,) = helperConfig.activeNetworkConfig();
        addConsumer(_lottery, vrfCoordinator, subId);
    }

    function addConsumer(address _lottery, address _vrfCoordinator, uint64 _subId) public {
        console.log("Adding consumer contract:", _lottery);
        console.log("Adding consumer _vrfCoordinator:", _vrfCoordinator);
        console.log("Adding consumer _subId:", _subId);

        vm.startBroadcast();
        VRFCoordinatorV2Mock(_vrfCoordinator).addConsumer(_subId, _lottery);
        vm.stopBroadcast();
    }

    function run() external {
        address lottery = DevOpsTools.get_most_recent_deployment("Lottery", block.chainid);
        addConsumerUsingConfig(lottery);
    }
}
