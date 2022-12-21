// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./DividendTracker.sol";
import "./interfaces/IMemeticSwapV1Router01.sol";
import "./interfaces/IMemeticSwapV1Pair.sol";
import "./libraries/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract WildWestToken is ERC20, Ownable {
    using SafeMath for uint256;

    IMemeticSwapV1Router01 public immutable router;
    ERC20 public immutable memetic;
    address public pair;

    bool private swapping;

    DividendTracker public dividendTracker;

    address private marketingWallet;
    address private teamWallet;

    uint256 public swapTokensAtAmount;

    uint256 public tradingActiveBlock = 0; // 0 means trading is not active
    uint256 public tradingActiveTimestamp = 0; // 0 means trading is not active

    bool public limitsInEffect = true;
    bool public tradingActive = false;
    bool public swapEnabled = false;

    uint256 public constant feeDivisor = 1e4;
    uint256 public constant taxDecayPeriod = 35 days;
    uint256 public constant maxJeetTax = 3500;

    uint256 public sellFee;
    uint256 public buyFee;

    uint256 public rewardsRatioForBuys;
    uint256 public marketingRatioForBuys;
    uint256 public liquidityRatioForBuys;
    uint256 public teamRatioForBuys;
    uint256 public burnRatioForBuys;
    uint256 public totalRatioForBuys;

    uint256 public rewardsRatioForSells;
    uint256 public marketingRatioForSells;
    uint256 public liquidityRatioForSells;
    uint256 public teamRatioForSells;
    uint256 public burnRatioForSells;
    uint256 public totalRatioForSells;

    uint256 public rewardsBalance;
    uint256 public liquidityBalance;
    uint256 public marketingBalance;
    uint256 public teamBalance;

    uint256 public gasForProcessing = 500000;

    mapping(address => bool) public automatedMarketMakerPairs;

    mapping(address => bool) private _isExcludedFromFees;
    mapping(address => bool) private _isBot;

    event ExcludeFromFees(address indexed account, bool isExcluded);
    event ExcludeMultipleAccountsFromFees(address[] accounts, bool isExcluded);
    event SetAutomatedMarketMakerPair(address indexed pair, bool indexed value);
    event GasForProcessingUpdated(
        uint256 indexed newValue,
        uint256 indexed oldValue
    );
    event SwapAndLiquify(
        uint256 tokensSwapped,
        uint256 ethReceived,
        uint256 tokensIntoLiqudity
    );
    event SendDividends(uint256 tokensSwapped, uint256 amount);
    event ProcessedDividendTracker(
        uint256 iterations,
        uint256 claims,
        uint256 lastProcessedIndex,
        bool indexed automatic,
        uint256 gas,
        address indexed processor
    );

    constructor() ERC20("Wild West Token", "WWT") {
        uint256 supply = 1e12 * (10**decimals());
        uint256 initialBurn = supply / 2;

        swapTokensAtAmount = ((supply - initialBurn) * 1) / 1e4;

        buyFee = 400;
        sellFee = 1000;

        rewardsRatioForBuys = 0;
        marketingRatioForBuys = 0;
        liquidityRatioForBuys = 1;
        teamRatioForBuys = 0;
        burnRatioForBuys = 0;

        totalRatioForBuys =
            rewardsRatioForBuys +
            marketingRatioForBuys +
            liquidityRatioForBuys +
            teamRatioForBuys +
            burnRatioForBuys;

        rewardsRatioForSells = 700;
        marketingRatioForSells = 200;
        liquidityRatioForSells = 0;
        teamRatioForSells = 100;
        burnRatioForSells = 0;

        totalRatioForSells =
            rewardsRatioForSells +
            marketingRatioForSells +
            liquidityRatioForSells +
            teamRatioForSells +
            burnRatioForSells;

        dividendTracker = new DividendTracker();
        marketingWallet = address(42);
        teamWallet = address(1337);
        router = IMemeticSwapV1Router01(
            0x1b3813aC0863afFF2b4E8716fcFeb5Bf382b1DD1
        );
        memetic = ERC20(0xE5Ca307249662fe2Dc4c91c91aab44ea8578E671);

        // exclude from receiving dividends
        dividendTracker.excludeFromDividends(address(dividendTracker));
        dividendTracker.excludeFromDividends(address(this));
        dividendTracker.excludeFromDividends(owner());
        dividendTracker.excludeFromDividends(address(router));
        dividendTracker.excludeFromDividends(address(0xdead));

        // exclude from paying fees
        excludeFromFees(owner(), true);
        excludeFromFees(address(this), true);
        excludeFromFees(address(0xdead), true);
        excludeFromFees(marketingWallet, true);

        _mint(address(0xdead), initialBurn);
        _mint(owner(), supply - initialBurn);
    }

    receive() external payable {}

    // excludes wallets and contracts from dividends (such as CEX hotwallets, etc.)
    function excludeFromDividends(address account) external onlyOwner {
        dividendTracker.excludeFromDividends(account);
    }

    // removes exclusion on wallets and contracts from dividends (such as CEX hotwallets, etc.)
    function includeInDividends(address account) external onlyOwner {
        dividendTracker.includeInDividends(account);
    }

    // once enabled, can never be turned off
    function enableTrading() external onlyOwner {
        require(!tradingActive, "Cannot re-enable trading");
        require(
            pair != address(0),
            "Pair must be set before trading can be enabled"
        );
        tradingActive = true;
        swapEnabled = true;
        tradingActiveBlock = block.number;
        tradingActiveTimestamp = block.timestamp;
    }

    // only use to disable contract sales if absolutely necessary (emergency use only)
    function updateSwapEnabled(bool enabled) external onlyOwner {
        swapEnabled = enabled;
    }

    function updateRatiosForBuys(
        uint256 _rewardsRatioForBuys,
        uint256 _marketingRatioForBuys,
        uint256 _liquidityRatioForBuys,
        uint256 _teamRatioForBuys,
        uint256 _burnRatioForBuys
    ) external onlyOwner {
        rewardsRatioForBuys = _rewardsRatioForBuys;
        marketingRatioForBuys = _marketingRatioForBuys;
        liquidityRatioForBuys = _liquidityRatioForBuys;
        teamRatioForBuys = _teamRatioForBuys;
        burnRatioForBuys = _burnRatioForBuys;

        totalRatioForBuys =
            rewardsRatioForBuys +
            marketingRatioForBuys +
            liquidityRatioForBuys +
            teamRatioForBuys +
            burnRatioForBuys;
    }

    function updateRatiosForSells(
        uint256 _rewardsRatioForSells,
        uint256 _marketingRatioForSells,
        uint256 _liquidityRatioForSells,
        uint256 _teamRatioForSells,
        uint256 _burnRatioForSells
    ) external onlyOwner {
        rewardsRatioForSells = _rewardsRatioForSells;
        marketingRatioForSells = _marketingRatioForSells;
        liquidityRatioForSells = _liquidityRatioForSells;
        teamRatioForSells = _teamRatioForSells;
        burnRatioForSells = _burnRatioForSells;

        totalRatioForSells =
            rewardsRatioForSells +
            marketingRatioForSells +
            liquidityRatioForSells +
            teamRatioForSells +
            burnRatioForSells;
    }

    function updateFees(uint256 _buyFee, uint256 _sellFee) external onlyOwner {
        buyFee = _buyFee;
        sellFee = _sellFee;
        require(buyFee + sellFee < 2500, "Fees cannot be more than 25%");
    }

    function airdropHolders(
        address[] memory wallets,
        uint256[] memory amountsInTokens
    ) external onlyOwner {
        require(
            wallets.length == amountsInTokens.length,
            "arrays must be the same length"
        );

        for (uint256 i = 0; i < wallets.length; i++) {
            address wallet = wallets[i];
            uint256 amount = amountsInTokens[i] * 1e18;
            _transfer(msg.sender, wallet, amount);
        }
    }

    function excludeFromFees(address account, bool excluded) public onlyOwner {
        _isExcludedFromFees[account] = excluded;

        emit ExcludeFromFees(account, excluded);
    }

    function excludeMultipleAccountsFromFees(
        address[] calldata accounts,
        bool excluded
    ) external onlyOwner {
        for (uint256 i = 0; i < accounts.length; i++) {
            _isExcludedFromFees[accounts[i]] = excluded;
        }

        emit ExcludeMultipleAccountsFromFees(accounts, excluded);
    }

    function setAutomatedMarketMakerPair(address pair_, bool value)
        external
        onlyOwner
    {
        require(
            pair != pair_,
            "The default swap pair cannot be removed from automatedMarketMakerPairs"
        );

        _setAutomatedMarketMakerPair(pair_, value);
    }

    function _setAutomatedMarketMakerPair(address pair_, bool value) private {
        automatedMarketMakerPairs[pair_] = value;

        if (value) {
            dividendTracker.excludeFromDividends(pair_);
        }

        emit SetAutomatedMarketMakerPair(pair_, value);
    }

    function setSwapPair(address pair_) external onlyOwner {
        pair = pair_;
        _setAutomatedMarketMakerPair(pair_, true);
    }

    function updateGasForProcessing(uint256 newValue) external onlyOwner {
        require(
            newValue != gasForProcessing,
            "Cannot update gasForProcessing to same value"
        );
        emit GasForProcessingUpdated(newValue, gasForProcessing);
        gasForProcessing = newValue;
    }

    function updateClaimWait(uint256 claimWait) external onlyOwner {
        dividendTracker.updateClaimWait(claimWait);
    }

    function getClaimWait() external view returns (uint256) {
        return dividendTracker.claimWait();
    }

    function getTotalDividendsDistributed() external view returns (uint256) {
        return dividendTracker.totalDividendsDistributed();
    }

    function isExcludedFromFees(address account) external view returns (bool) {
        return _isExcludedFromFees[account];
    }

    function withdrawableDividendOf(address account)
        external
        view
        returns (uint256)
    {
        return dividendTracker.withdrawableDividendOf(account);
    }

    function dividendTokenBalanceOf(address account)
        external
        view
        returns (uint256)
    {
        return dividendTracker.holderBalance(account);
    }

    function getAccountDividendsInfo(address account)
        external
        view
        returns (
            address,
            int256,
            int256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        return dividendTracker.getAccount(account);
    }

    function getAccountDividendsInfoAtIndex(uint256 index)
        external
        view
        returns (
            address,
            int256,
            int256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        return dividendTracker.getAccountAtIndex(index);
    }

    function processDividendTracker(uint256 gas) external {
        (
            uint256 iterations,
            uint256 claims,
            uint256 lastProcessedIndex
        ) = dividendTracker.process(gas);
        emit ProcessedDividendTracker(
            iterations,
            claims,
            lastProcessedIndex,
            false,
            gas,
            tx.origin
        );
    }

    function claim() external {
        dividendTracker.processAccount(payable(msg.sender), false);
    }

    function getLastProcessedIndex() external view returns (uint256) {
        return dividendTracker.getLastProcessedIndex();
    }

    function getNumberOfDividendTokenHolders() external view returns (uint256) {
        return dividendTracker.getNumberOfTokenHolders();
    }

    function getNumberOfDividends() external view returns (uint256) {
        return dividendTracker.totalBalance();
    }

    function blacklistBot(address[] memory bots_, bool status_)
        public
        onlyOwner
    {
        if (status_ == true) {
            require(
                block.number < tradingActiveBlock + 300,
                "too late to blacklist bots"
            );
        }

        for (uint256 i = 0; i < bots_.length; i++) {
            if (bots_[i] != address(pair) && bots_[i] != address(router)) {
                _isBot[bots_[i]] = status_;
            }
        }
    }

    function getJeetTax() public view returns (uint256) {
        uint256 timeSinceLaunch = block.timestamp - tradingActiveTimestamp;

        if (timeSinceLaunch >= taxDecayPeriod) {
            return 0;
        }

        return maxJeetTax - (maxJeetTax * timeSinceLaunch) / taxDecayPeriod;
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(!_isBot[to] && !_isBot[from], "unable to trade");

        if (amount == 0) {
            super._transfer(from, to, 0);
            return;
        }

        if (!tradingActive) {
            require(
                _isExcludedFromFees[from] || _isExcludedFromFees[to],
                "Trading is not active yet."
            );
        }

        uint256 contractTokenBalance = balanceOf(address(this));
        bool canSwap = contractTokenBalance >= swapTokensAtAmount;

        if (
            canSwap &&
            swapEnabled &&
            !swapping &&
            !automatedMarketMakerPairs[from] &&
            !_isExcludedFromFees[from] &&
            !_isExcludedFromFees[to]
        ) {
            swapping = true;
            swapAndDistributeFees();
            swapping = false;
        }

        bool takeFee = !swapping;

        // if any account belongs to _isExcludedFromFee account then remove the fee
        if (_isExcludedFromFees[from] || _isExcludedFromFees[to]) {
            takeFee = false;
        }

        uint256 fees = 0;

        // no taxes on transfers (non-buys/sells)
        if (takeFee) {
            bool isBuy = automatedMarketMakerPairs[to];
            bool isSell = automatedMarketMakerPairs[from];

            if (isBuy) {
                fees = amount.mul(buyFee).div(feeDivisor);
                processBuyFee(from, fees);
            } else if (isSell) {
                fees = amount.mul(sellFee).div(feeDivisor);

                uint256 jeetFee = amount.mul(getJeetTax()).div(feeDivisor);
                if (jeetFee > 0) {
                    super._transfer(from, address(0xdead), jeetFee);
                    amount -= jeetFee;
                }

                processSellFee(from, fees);
            }

            amount -= fees;
        }

        super._transfer(from, to, amount);

        dividendTracker.setBalance(payable(from), balanceOf(from));
        dividendTracker.setBalance(payable(to), balanceOf(to));

        if (!swapping && gasForProcessing > 0) {
            uint256 gas = gasForProcessing;

            try dividendTracker.process(gas) returns (
                uint256 iterations,
                uint256 claims,
                uint256 lastProcessedIndex
            ) {
                emit ProcessedDividendTracker(
                    iterations,
                    claims,
                    lastProcessedIndex,
                    true,
                    gas,
                    tx.origin
                );
            } catch {}
        }
    }

    function swapTokensForEth(uint256 tokenAmount) private returns (uint256) {
        uint256 initialBalance = address(this).balance;
        address[] memory path = new address[](3);

        path[0] = address(this);
        path[1] = address(memetic);
        path[2] = router.wpom();

        _approve(address(this), address(router), tokenAmount);
        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );

        return address(this).balance.sub(initialBalance);
    }

    function processBuyFee(address from, uint256 fee) private {
        if (fee == 0) {
            return;
        }

        uint256 rewardsShare = fee.mul(rewardsRatioForBuys).div(
            totalRatioForBuys
        );
        uint256 marketingShare = fee.mul(marketingRatioForBuys).div(
            totalRatioForBuys
        );
        uint256 liquidityShare = fee.mul(liquidityRatioForBuys).div(
            totalRatioForBuys
        );
        uint256 teamShare = fee.mul(teamRatioForBuys).div(totalRatioForBuys);
        uint256 burnShare = fee
            .sub(rewardsShare)
            .sub(marketingShare)
            .sub(liquidityShare)
            .sub(teamShare);

        super._transfer(from, address(0xdead), burnShare);
        super._transfer(
            from,
            address(this),
            liquidityShare + rewardsShare + marketingShare + teamShare
        );

        rewardsBalance += rewardsShare;
        liquidityBalance += liquidityShare;
        marketingBalance += marketingShare;
        teamBalance += teamShare;
    }

    function processSellFee(address from, uint256 fee) private {
        if (fee == 0) {
            return;
        }

        uint256 rewardsShare = fee.mul(rewardsRatioForSells).div(
            totalRatioForSells
        );
        uint256 marketingShare = fee.mul(marketingRatioForSells).div(
            totalRatioForSells
        );
        uint256 liquidityShare = fee.mul(liquidityRatioForSells).div(
            totalRatioForSells
        );
        uint256 teamShare = fee.mul(teamRatioForSells).div(totalRatioForSells);
        uint256 burnShare = fee
            .sub(rewardsShare)
            .sub(marketingShare)
            .sub(liquidityShare)
            .sub(teamShare);

        super._transfer(from, address(0xdead), burnShare);
        super._transfer(
            from,
            address(this),
            liquidityShare + rewardsShare + marketingShare + teamShare
        );

        rewardsBalance += rewardsShare;
        liquidityBalance += liquidityShare;
        marketingBalance += marketingShare;
        teamBalance += teamShare;
    }

    function swapAndLiquify(uint256 tokensAmount) private {
        uint256 half = tokensAmount.div(2);
        uint256 otherHalf = tokensAmount.sub(half);
        address[] memory path = new address[](2);

        path[0] = address(this);
        path[1] = address(memetic);

        _approve(address(this), address(router), half);
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            half,
            0,
            path,
            pair,
            block.timestamp
        );

        super._transfer(address(this), pair, otherHalf);
        IMemeticSwapV1Pair(pair).mint(address(0xdead));
    }

    function swapAndDistributeFees() private {
        uint256 contractTokenBalance = balanceOf(address(this));

        if (contractTokenBalance == 0) {
            return;
        }

        if (liquidityBalance > 0) {
            swapAndLiquify(liquidityBalance);
            liquidityBalance = 0;
        }

        if (marketingBalance > 0) {
            uint256 ethForMarketing = swapTokensForEth(marketingBalance);
            marketingBalance = 0;
            (bool success, ) = address(marketingWallet).call{
                value: ethForMarketing
            }("");
            require(success, "Failed to send ETH to marketing wallet");
        }

        if (teamBalance > 0) {
            uint256 ethForTeam = swapTokensForEth(teamBalance);
            teamBalance = 0;
            (bool success, ) = address(teamWallet).call{value: ethForTeam}("");
            require(success, "Failed to send ETH to team wallet");
        }

        if (rewardsBalance > 0) {
            uint256 ethForRewards = swapTokensForEth(rewardsBalance);
            rewardsBalance = 0;
            (bool success, ) = address(dividendTracker).call{
                value: ethForRewards
            }("");
            require(success, "Failed to send ETH to dividend tracker");
        }
    }

    function withdrawStuckEth() external onlyOwner {
        (bool success, ) = address(msg.sender).call{
            value: address(this).balance
        }("");
        require(success, "Stuck ETH withdrawal failed.");
    }

    function setSwapThreshold(uint256 amount) external onlyOwner {
        swapTokensAtAmount = amount;
    }
}
