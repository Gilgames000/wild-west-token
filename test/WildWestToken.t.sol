// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "../src/interfaces/IMemeticSwapV1Factory.sol";
import "../src/interfaces/IMemeticSwapV1Pair.sol";
import "../src/WildWestToken.sol";
import "../script/DeployToken.s.sol";
import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract WildWestTokenTest is Test {
    uint256 mainnetFork;
    address deployer = 0xCcb50a6A2C58Ae55E3aa349289C4f9F697669fC9;
    IERC20 memetic = IERC20(0xE5Ca307249662fe2Dc4c91c91aab44ea8578E671);
    address memeticTreasury = 0x144864b92686a09AB0A3af3b4a0AB1fBD02b093F;
    IMemeticSwapV1Router01 router =
        IMemeticSwapV1Router01(0x1b3813aC0863afFF2b4E8716fcFeb5Bf382b1DD1);
    WildWestToken wwt;
    address alice = address(0xa11ce);

    function setUp() public {
        console.log("Test contract address: ", address(this));
        console.log("Sender address: ", msg.sender);
        console.log("Origin address: ", tx.origin);

        vm.label(address(memetic), "MEMETIC");
        vm.label(memeticTreasury, "MEMETIC_TREASURY");
        vm.label(address(router), "ROUTER");
        vm.label(address(this), "TEST_CONTRACT");
        vm.label(msg.sender, "TEST_SENDER");
        vm.label(tx.origin, "TEST_ORIGIN");
        vm.label(alice, "ALICE");

        mainnetFork = vm.createSelectFork("https://mainnet-rpc3.memescan.io");

        vm.startPrank(memeticTreasury);
        memetic.transfer(address(this), memetic.balanceOf(memeticTreasury));
        vm.stopPrank();
        assertEq(memetic.balanceOf(memeticTreasury), 0);
        assertGt(memetic.balanceOf(address(this)), 0);

        wwt = new WildWestToken();
        address memeticswapV1Pair = IMemeticSwapV1Factory(
            wwt.router().factory()
        ).createPair(address(wwt), address(wwt.memetic()), false);
        wwt.setSwapPair(memeticswapV1Pair);

        uint256 amountWwt = wwt.balanceOf(address(this)) / 2;
        uint256 amountMemetic = 1e4 ether;
        wwt.approve(address(router), amountWwt);
        wwt.memetic().approve(address(router), amountMemetic);
        router.addLiquidity(
            address(wwt),
            address(wwt.memetic()),
            amountWwt,
            amountMemetic,
            0,
            0,
            // address(0xdead),
            msg.sender,
            block.timestamp + 30 minutes
        );
        wwt.enableTrading();

        assertEq(wwt.balanceOf(address(this)), wwt.totalSupply() / 4);
        memetic.transfer(alice, 100 ether);
    }

    function testBuySell() public {
        console.log("WildWestToken deployed at:", address(wwt));
        console.log("Deployer WWT balance: ", wwt.balanceOf(deployer));
        console.log(
            "Test contract WWT balance: ",
            wwt.balanceOf(address(this))
        );
        console.log("Test sender WWT balance: ", wwt.balanceOf(msg.sender));
        console.log("TradingActive:", wwt.tradingActive());
        console.log("SwapEnabled:", wwt.swapEnabled());
        console.log("Memetic:", address(wwt.memetic()));
        console.log("SwapTokensAtAmount:", wwt.swapTokensAtAmount());

        uint256 amountIn = 100 ether;
        address[] memory path = new address[](2);

        path[0] = address(memetic);
        path[1] = address(wwt);

        vm.startPrank(alice);
        memetic.approve(address(router), amountIn);
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountIn,
            0,
            path,
            alice,
            block.timestamp + 30 minutes
        );
        vm.stopPrank();

        uint256 amountOut = wwt.balanceOf(alice);
        assertGt(amountOut, 0);

        path[0] = address(wwt);
        path[1] = address(memetic);

        vm.startPrank(alice);
        wwt.approve(address(router), amountOut);
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amountOut / 2,
            0,
            path,
            alice,
            block.timestamp + 30 minutes
        );
        wwt.transfer(address(0xcafebabe), 1); // to trigger the tax distribution
        vm.stopPrank();

        console.log("Swap pair:", wwt.pair());
        console.log(
            "AutomatedMarketMakerPairs:",
            wwt.automatedMarketMakerPairs(wwt.pair())
        );
        console.log("Contract token balance:", wwt.balanceOf(address(wwt)));
        console.log("Contract ETH balance:", address(wwt).balance);
        console.log(
            "Can swap:",
            wwt.balanceOf(address(wwt)) >= wwt.swapTokensAtAmount()
        );
        console.log("Alice ETH balance: ", alice.balance);
        console.log(
            "Dividend tracker ETH balance: ",
            address(wwt.dividendTracker()).balance
        );
        console.log(
            "Dividend tracker WWT balance: ",
            wwt.balanceOf(address(wwt.dividendTracker()))
        );
        console.log(
            "Marketing wallet ETH balance: ",
            address(wwt.marketingWallet()).balance
        );
        console.log(
            "Marketing wallet WWT balance: ",
            wwt.balanceOf(address(wwt.marketingWallet()))
        );
        console.log(
            "Team wallet ETH balance: ",
            address(wwt.teamWallet()).balance
        );
        console.log(
            "Team wallet WWT balance: ",
            wwt.balanceOf(address(wwt.teamWallet()))
        );
    }

    function testGetJeetTax() public {
        uint256 maxJeetTax = 2000;
        uint256 decayPeriod = 45 days;
        uint256 decayStart = block.timestamp;

        assertEq(wwt.getJeetTax(), maxJeetTax);

        vm.warp(decayStart + 30 days);
        assertEq(wwt.getJeetTax(), 667);

        vm.warp(decayStart + decayPeriod / 2);
        assertEq(wwt.getJeetTax(), maxJeetTax / 2);

        vm.warp(decayStart + decayPeriod);
        assertEq(wwt.getJeetTax(), 0);

        vm.warp(decayStart + decayPeriod * 2);
        assertEq(wwt.getJeetTax(), 0);
    }
}
