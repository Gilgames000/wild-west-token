// SPDX-License-Identifier:AGPL-3.0-only
pragma solidity ^0.8.17;

import "../src/WildWestToken.sol";
import "../src/interfaces/IMemeticSwapV1Factory.sol";
import "../src/interfaces/IMemeticSwapV1Router01.sol";
import "forge-std/Test.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract DeployWildWestToken is Test {
    using Strings for uint256;

    function setUp() public view {
        console.log(
            "Running script on chain with ID:",
            block.chainid.toString()
        );
    }

    function run() external {
        vm.startBroadcast();
        WildWestToken wwt = new WildWestToken();
        address memeticswapV1Pair = IMemeticSwapV1Factory(
            wwt.router().factory()
        ).createPair(address(wwt), address(wwt.memetic()), false);
        wwt.setSwapPair(memeticswapV1Pair);
        wwt.enableTrading();
        vm.stopBroadcast();
        console.log("WildWestToken deployed at:", address(wwt));
    }

    function addWildWestTokenPair(address payable _wwt, address _pair)
        external
    {
        WildWestToken wwt = WildWestToken(_wwt);
        vm.startBroadcast();
        wwt.setAutomatedMarketMakerPair(_pair, true);
        vm.stopBroadcast();
        console.log("Added pair:", _pair);
    }

    function enableTrading(address payable _wwt) external {
        WildWestToken wwt = WildWestToken(_wwt);
        vm.startBroadcast();
        wwt.enableTrading();
        vm.stopBroadcast();
        console.log("Trading enabled");
    }

    function getInfo(address payable _wwt) external {
        WildWestToken wwt = WildWestToken(_wwt);
        console.log("WildWestToken deployed at:", address(wwt));
        console.log("Swap pair:", wwt.pair());
        console.log(
            "AutomatedMarketMakerPairs:",
            wwt.automatedMarketMakerPairs(wwt.pair())
        );
        console.log("TradingActive:", wwt.tradingActive());
        console.log("SwapEnabled:", wwt.swapEnabled());
        console.log("Memetic:", address(wwt.memetic()));
        console.log("SwapTokensAtAmount:", wwt.swapTokensAtAmount());
        console.log("Contract token balance:", wwt.balanceOf(address(wwt)));
        console.log("Contract ETH balance:", address(wwt).balance);
        console.log(
            "Can swap:",
            wwt.balanceOf(address(wwt)) >= wwt.swapTokensAtAmount()
        );
    }

    function sell(address payable _wwt) external {
        WildWestToken wwt = WildWestToken(_wwt);
        address[] memory path = new address[](2);
        path[0] = address(wwt);
        path[1] = address(wwt.memetic());

        uint256 userBalance = wwt.balanceOf(address(msg.sender));
        console.log("User balance:", userBalance);
        console.log("Selling tokens with beneficiary:", msg.sender);
        IMemeticSwapV1Router01 router = wwt.router();

        vm.startBroadcast();
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            10000 * 10**wwt.decimals(),
            0,
            path,
            msg.sender,
            block.timestamp + 30 minutes
        );
        vm.stopBroadcast();

        console.log("Sold");
    }

    function buy(address payable _wwt) external {
        WildWestToken wwt = WildWestToken(_wwt);
        address[] memory path = new address[](2);
        path[0] = address(wwt.memetic());
        path[1] = address(wwt);

        uint256 userBalance = wwt.memetic().balanceOf(address(msg.sender));
        console.log("User balance:", userBalance);
        console.log("Buying tokens with beneficiary:", msg.sender);
        IMemeticSwapV1Router01 router = wwt.router();

        vm.startBroadcast();
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            1 * 10**wwt.memetic().decimals(),
            0,
            path,
            msg.sender,
            block.timestamp + 30 minutes
        );
        vm.stopBroadcast();

        console.log("Bought");
    }

    function setSwapThreshold(address payable _wwt, uint256 _amount) external {
        WildWestToken wwt = WildWestToken(_wwt);
        vm.startBroadcast();
        wwt.setSwapThreshold(_amount);
        vm.stopBroadcast();
        console.log("Swap threshold set to:", _amount);
    }
}
