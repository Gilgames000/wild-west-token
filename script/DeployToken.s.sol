// SPDX-License-Identifier:AGPL-3.0-only
pragma solidity ^0.8.17;

import "../src/WildWestToken.sol";
import "../src/interfaces/IMemeticSwapV1Factory.sol";
import "../src/interfaces/IMemeticSwapV1Router01.sol";
import "forge-std/Test.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract DeployToken is Test {
    using Strings for uint256;

    function setUp() public view {
        console.log(
            "Running script on chain with ID:",
            block.chainid.toString()
        );
    }

    function run() external returns (WildWestToken) {
        vm.startBroadcast();
        WildWestToken wwt = new WildWestToken();
        // address memeticswapV1Pair = IMemeticSwapV1Factory(
        //     wwt.router().factory()
        // ).createPair(address(wwt), address(wwt.memetic()), false);
        // wwt.setSwapPair(memeticswapV1Pair);
        // addLiquidity(
        //     payable(wwt),
        //     wwt.balanceOf(msg.sender) / 2,
        //     1000 * 10**wwt.memetic().decimals()
        // );
        // wwt.enableTrading();
        vm.stopBroadcast();
        console.log("WildWestToken deployed at:", address(wwt));

        return wwt;
    }

    function setSwapPair(address payable _wwt, address _pair) external {
        WildWestToken wwt = WildWestToken(_wwt);
        vm.broadcast();
        wwt.setSwapPair(_pair);
    }

    function addAMMPair(address payable _wwt, address _pair) external {
        WildWestToken wwt = WildWestToken(_wwt);
        vm.broadcast();
        wwt.setAutomatedMarketMakerPair(_pair, true);
        console.log("Added pair:", _pair);
    }

    function enableTrading(address payable _wwt) external {
        WildWestToken wwt = WildWestToken(_wwt);
        vm.broadcast();
        wwt.enableTrading();
        console.log("Trading enabled");
    }

    function addLiquidity(
        address payable _wwt,
        uint256 _amount,
        uint256 _amountMemetic
    ) internal {
        WildWestToken wwt = WildWestToken(_wwt);
        IMemeticSwapV1Router01 router = wwt.router();

        wwt.approve(address(router), _amount);
        wwt.memetic().approve(address(router), _amountMemetic);
        router.addLiquidity(
            address(wwt),
            address(wwt.memetic()),
            _amount,
            _amountMemetic,
            0,
            0,
            // address(0xdead),
            msg.sender,
            block.timestamp + 30 minutes
        );

        console.log("Added liquidity");
    }

    function getInfo(address payable _wwt) external {
        WildWestToken wwt = WildWestToken(_wwt);
        console.log("WildWestToken deployed at:", address(wwt));
        console.log("Swap pair:", wwt.pair());
        console.log(
            "Swap pair is AMM:",
            wwt.automatedMarketMakerPairs(wwt.pair())
        );
        console.log("TradingActive:", wwt.tradingActive());
        console.log("SwapEnabled:", wwt.swapEnabled());
        console.log("Memetic:", address(wwt.memetic()));
        console.log("SwapTokensAtAmount:", wwt.swapTokensAtAmount());
        console.log("MarketingWallet:", address(wwt.marketingWallet()));
        console.log(
            "MarketingWallet ETH balance:",
            address(wwt.marketingWallet()).balance
        );
        console.log("TeamWallet:", address(wwt.teamWallet()));
        console.log(
            "TeamWallet ETH balance:",
            address(wwt.teamWallet()).balance
        );
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
            1 * 10**wwt.decimals(),
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

    function toggleJeetTax(address payable _wwt, bool enabled) external {
        WildWestToken wwt = WildWestToken(_wwt);
        vm.startBroadcast();
        wwt.toggleJeetTax(enabled);
        vm.stopBroadcast();
        console.log("Jeet tax enabled:", enabled);
    }

    function setJeetTax(address payable _wwt, uint256 _fee) external {
        WildWestToken wwt = WildWestToken(_wwt);
        vm.startBroadcast();
        wwt.setJeetTax(_fee);
        vm.stopBroadcast();
        console.log("Jeet tax set to:", _fee);
    }
}
