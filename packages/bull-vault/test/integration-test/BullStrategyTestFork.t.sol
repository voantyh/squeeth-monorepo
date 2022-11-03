pragma solidity =0.7.6;

pragma abicoder v2;

// test dependency
import "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
//interface
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {IController} from "squeeth-monorepo/interfaces/IController.sol";
import {IEulerMarkets} from "../../src/interface/IEulerMarkets.sol";
import {IEulerEToken} from "../../src/interface/IEulerEToken.sol";
import {IEulerDToken} from "../../src/interface/IEulerDToken.sol";
// contract
import {BullStrategy} from "../../src/BullStrategy.sol";
import {CrabStrategyV2} from "squeeth-monorepo/strategy/CrabStrategyV2.sol";
import {Controller} from "squeeth-monorepo/core/Controller.sol";
// lib
import {VaultLib} from "squeeth-monorepo/libs/VaultLib.sol";
import {StrategyMath} from "squeeth-monorepo/strategy/base/StrategyMath.sol"; // StrategyMath licensed under AGPL-3.0-only
import {UniOracle} from "../../src/UniOracle.sol";

/**
 * @notice Ropsten fork testing
 */
contract BullStrategyTestFork is Test {
    using StrategyMath for uint256;

    uint32 internal constant TWAP = 420;

    BullStrategy internal bullStrategy;
    CrabStrategyV2 internal crabV2;
    Controller internal controller;

    uint256 internal user1Pk;
    address internal user1;
    address internal weth;
    address internal usdc;
    address internal euler;
    address internal eulerMarketsModule;
    address internal eToken;
    address internal dToken;
    address internal wPowerPerp;
    uint256 internal deployerPk;
    address internal deployer;

    function setUp() public {
        string memory FORK_URL = vm.envString("FORK_URL");
        vm.createSelectFork(FORK_URL, 15781550);

        vm.startPrank(deployer);
        euler = 0x27182842E098f60e3D576794A5bFFb0777E025d3;
        eulerMarketsModule = 0x3520d5a913427E6F0D6A83E07ccD4A4da316e4d3;
        controller = Controller(0x64187ae08781B09368e6253F9E94951243A493D5);
        crabV2 = CrabStrategyV2(0x3B960E47784150F5a63777201ee2B15253D713e8);
        bullStrategy =
        new BullStrategy(address(crabV2), address(controller), euler, eulerMarketsModule);
        usdc = controller.quoteCurrency();
        weth = controller.weth();
        eToken = IEulerMarkets(eulerMarketsModule).underlyingToEToken(weth);
        dToken = IEulerMarkets(eulerMarketsModule).underlyingToDToken(usdc);
        wPowerPerp = controller.wPowerPerp();
        vm.stopPrank();

        user1Pk = 0xA11CE;
        user1 = vm.addr(user1Pk);

        vm.label(user1, "User 1");
        vm.label(address(bullStrategy), "BullStrategy");
        vm.label(euler, "Euler");
        vm.label(eulerMarketsModule, "EulerMarkets");
        vm.label(usdc, "USDC");
        vm.label(weth, "WETH");
        vm.label(wPowerPerp, "oSQTH");
        vm.label(address(crabV2), "crabV2");

        vm.deal(user1, 100000000e18);
        // this is a crab whale, get some crab token from
        vm.prank(0x06CECFbac34101aE41C88EbC2450f8602b3d164b);
        IERC20(crabV2).transfer(user1, 100e18);
        // some WETH and USDC rich address
        vm.prank(0x57757E3D981446D585Af0D9Ae4d7DF6D64647806);
        IERC20(weth).transfer(user1, 10000e18);
    }

    function testInitialDeposit() public {
        uint256 crabToDeposit = 10e18;
        uint256 bullCrabBalanceBefore = bullStrategy.getCrabBalance();

        vm.startPrank(user1);
        (uint256 wethToLend, uint256 usdcToBorrow) = _deposit(crabToDeposit);
        vm.stopPrank();

        uint256 bullCrabBalanceAfter = bullStrategy.getCrabBalance();

        assertEq(bullCrabBalanceAfter.sub(crabToDeposit), bullCrabBalanceBefore);
        assertEq(bullStrategy.balanceOf(user1), crabToDeposit);
        assertEq(IEulerDToken(dToken).balanceOf(address(bullStrategy)), usdcToBorrow);
        assertTrue(wethToLend.sub(IEulerEToken(eToken).balanceOfUnderlying(address(bullStrategy))) <= 1);
        assertEq(IERC20(usdc).balanceOf(user1), usdcToBorrow);
    }

    function testSecondDeposit() public {
        uint256 crabToDepositInitially = 10e18;
        uint256 bullCrabBalanceBefore = bullStrategy.getCrabBalance();

        vm.startPrank(user1);
        (uint256 wethToLend, uint256 usdcToBorrow) = _deposit(crabToDepositInitially);
        vm.stopPrank();

        uint256 bullCrabBalanceAfter = bullStrategy.getCrabBalance();

        assertEq(bullCrabBalanceAfter.sub(crabToDepositInitially), bullCrabBalanceBefore);
        assertEq(bullStrategy.balanceOf(user1), crabToDepositInitially);
        assertEq(IEulerDToken(dToken).balanceOf(address(bullStrategy)), usdcToBorrow);
        assertTrue(wethToLend.sub(IEulerEToken(eToken).balanceOfUnderlying(address(bullStrategy))) <= 1);
        assertEq(IERC20(usdc).balanceOf(user1), usdcToBorrow);

        bullCrabBalanceBefore = bullStrategy.getCrabBalance();
        uint256 userUsdcBalanceBefore = IERC20(usdc).balanceOf(user1);
        uint256 userBullBalanceBefore = bullStrategy.balanceOf(user1);
        uint256 crabToDepositSecond = 7e18;
        uint256 bullToMint = _calcBullToMint(crabToDepositSecond);
        vm.startPrank(user1);
        (uint256 wethToLendSecond, uint256 usdcToBorrowSecond) = _deposit(crabToDepositSecond);
        vm.stopPrank();

        bullCrabBalanceAfter = bullStrategy.getCrabBalance();

        assertEq(bullCrabBalanceAfter.sub(crabToDepositSecond), bullCrabBalanceBefore);
        assertEq(bullStrategy.balanceOf(user1).sub(userBullBalanceBefore), bullToMint);
        assertEq(IEulerDToken(dToken).balanceOf(address(bullStrategy)).sub(usdcToBorrow), usdcToBorrowSecond);
        assertTrue(wethToLendSecond.sub(IEulerEToken(eToken).balanceOfUnderlying(address(bullStrategy)).sub(wethToLend)) <= 1);
        assertEq(IERC20(usdc).balanceOf(user1).sub(usdcToBorrowSecond), userUsdcBalanceBefore);
    }

    function testWithdraw() public {
        uint256 crabToDeposit = 15e18;
        uint256 bullToMint = _calcBullToMint(crabToDeposit);

        // crabby deposit into bull
        vm.startPrank(user1);
        _deposit(crabToDeposit);
        vm.stopPrank();

        (uint256 wPowerPerpToRedeem, uint256 crabToRedeem) = _calcWPowerPerpAndCrabNeededForWithdraw(bullToMint);
        uint256 usdcToRepay = _calcUsdcNeededForWithdraw(bullToMint);
        uint256 wethToWithdraw = _calcWethToWithdraw(bullToMint);
        // transfer some oSQTH from some squeether
        vm.prank(0x56178a0d5F301bAf6CF3e1Cd53d9863437345Bf9);
        IERC20(wPowerPerp).transfer(user1, wPowerPerpToRedeem);

        uint256 userBullBalanceBefore = bullStrategy.balanceOf(user1);
        uint256 ethInLendingBefore = IEulerEToken(eToken).balanceOfUnderlying(address(bullStrategy));
        uint256 usdcBorrowedBefore = IEulerDToken(dToken).balanceOf(address(bullStrategy));
        uint256 userUsdcBalanceBefore = IERC20(usdc).balanceOf(user1);
        uint256 userWPowerPerpBalanceBefore = IERC20(wPowerPerp).balanceOf(user1);
        uint256 crabBalanceBefore = crabV2.balanceOf(address(bullStrategy));

        vm.startPrank(user1);
        IERC20(usdc).approve(address(bullStrategy), usdcToRepay);
        IERC20(wPowerPerp).approve(address(bullStrategy), wPowerPerpToRedeem);
        bullStrategy.withdraw(bullToMint);
        vm.stopPrank();

        assertEq(
            usdcBorrowedBefore.sub(usdcToRepay),
            IEulerDToken(dToken).balanceOf(address(bullStrategy)),
            "Bull USDC debt amount mismatch"
        );
        assertEq(
            ethInLendingBefore.sub(wethToWithdraw),
            IEulerEToken(eToken).balanceOfUnderlying(address(bullStrategy)),
            "Bull ETH in leverage amount mismatch"
        );
        assertEq(userUsdcBalanceBefore.sub(usdcToRepay), IERC20(usdc).balanceOf(user1), "User1 USDC balance mismatch");
        assertEq(userBullBalanceBefore.sub(bullToMint), bullStrategy.balanceOf(user1), "User1 bull balance mismatch");
        assertEq(
            userWPowerPerpBalanceBefore.sub(wPowerPerpToRedeem),
            IERC20(wPowerPerp).balanceOf(user1),
            "User1 oSQTH balance mismatch"
        );
        assertEq(
            crabBalanceBefore.sub(crabToRedeem), crabV2.balanceOf(address(bullStrategy)), "Bull ccrab balance mismatch"
        );
    }

    /**
     *
     * /************************************************************* Fuzz testing is awesome! ************************************************************
     */
    function testFuzzingDeposit(uint256 _crabAmount) public {
        _crabAmount = bound(_crabAmount, 0, IERC20(crabV2).balanceOf(user1));

        uint256 bullToMint = _calcBullToMint(_crabAmount);
        (uint256 wethToLend, uint256 usdcToBorrow) = _calcCollateralAndBorrowAmount(_crabAmount);
        uint256 userBullBalanceBefore = bullStrategy.balanceOf(user1);
        uint256 ethInLendingBefore = IEulerEToken(eToken).balanceOfUnderlying(address(bullStrategy));
        uint256 usdcBorrowedBefore = IEulerDToken(dToken).balanceOf(address(bullStrategy));
        uint256 userUsdcBalanceBefore = IERC20(usdc).balanceOf(user1);

        vm.startPrank(user1);
        IERC20(crabV2).approve(address(bullStrategy), _crabAmount);
        bullStrategy.deposit{value: wethToLend}(_crabAmount);
        vm.stopPrank();

        assertEq(bullStrategy.balanceOf(user1).sub(userBullBalanceBefore), bullToMint);
        assertTrue(
            wethToLend.sub(IEulerEToken(eToken).balanceOfUnderlying(address(bullStrategy)).sub(ethInLendingBefore)) <= 2
        );
        assertEq(IEulerDToken(dToken).balanceOf(address(bullStrategy)).sub(usdcBorrowedBefore), usdcToBorrow);
        assertEq(IERC20(usdc).balanceOf(user1).sub(userUsdcBalanceBefore), usdcToBorrow);
    }

    function testFuzzingWithdraw(uint256 _crabAmount) public {
        // use bound() instead of vm.assume for better performance in fuzzing
        _crabAmount = bound(_crabAmount, 1e18, IERC20(crabV2).balanceOf(user1));

        uint256 bullToMint = _calcBullToMint(_crabAmount);
        (uint256 wethToLend,) = _calcCollateralAndBorrowAmount(_crabAmount);
        vm.startPrank(user1);
        IERC20(crabV2).approve(address(bullStrategy), _crabAmount);
        bullStrategy.deposit{value: wethToLend}(_crabAmount);
        vm.stopPrank();

        (uint256 wPowerPerpToRedeem, uint256 crabToRedeem) = _calcWPowerPerpAndCrabNeededForWithdraw(bullToMint);
        uint256 usdcToRepay = _calcUsdcNeededForWithdraw(bullToMint);
        uint256 wethToWithdraw = _calcWethToWithdraw(bullToMint);
        // transfer some oSQTH from some squeether
        vm.prank(0x56178a0d5F301bAf6CF3e1Cd53d9863437345Bf9);
        IERC20(wPowerPerp).transfer(user1, wPowerPerpToRedeem);

        uint256 userBullBalanceBefore = bullStrategy.balanceOf(user1);
        uint256 ethInLendingBefore = IEulerEToken(eToken).balanceOfUnderlying(address(bullStrategy));
        uint256 usdcBorrowedBefore = IEulerDToken(dToken).balanceOf(address(bullStrategy));
        uint256 userUsdcBalanceBefore = IERC20(usdc).balanceOf(user1);
        uint256 userWPowerPerpBalanceBefore = IERC20(wPowerPerp).balanceOf(user1);
        uint256 crabBalanceBefore = crabV2.balanceOf(address(bullStrategy));

        vm.startPrank(user1);
        IERC20(usdc).approve(address(bullStrategy), usdcToRepay);
        IERC20(wPowerPerp).approve(address(bullStrategy), wPowerPerpToRedeem);
        bullStrategy.withdraw(bullToMint);
        vm.stopPrank();

        assertEq(
            usdcBorrowedBefore.sub(usdcToRepay),
            IEulerDToken(dToken).balanceOf(address(bullStrategy)),
            "Bull USDC debt amount mismatch"
        );
        assertEq(
            ethInLendingBefore.sub(wethToWithdraw),
            IEulerEToken(eToken).balanceOfUnderlying(address(bullStrategy)),
            "Bull ETH in leverage amount mismatch"
        );
        assertEq(userUsdcBalanceBefore.sub(usdcToRepay), IERC20(usdc).balanceOf(user1), "User1 USDC balance mismatch");
        assertEq(userBullBalanceBefore.sub(bullToMint), bullStrategy.balanceOf(user1), "User1 bull balance mismatch");
        assertEq(
            userWPowerPerpBalanceBefore.sub(wPowerPerpToRedeem),
            IERC20(wPowerPerp).balanceOf(user1),
            "User1 oSQTH balance mismatch"
        );
        assertEq(
            crabBalanceBefore.sub(crabToRedeem), crabV2.balanceOf(address(bullStrategy)), "Bull ccrab balance mismatch"
        );
    }

    /**
     *
     * /************************************************************* Helper functions for testing! ********************************************************
     */
    function _deposit(uint256 _crabToDeposit) internal returns (uint256, uint256) {
        (uint256 wethToLend, uint256 usdcToBorrow) = _calcCollateralAndBorrowAmount(_crabToDeposit);

        IERC20(crabV2).approve(address(bullStrategy), _crabToDeposit);
        bullStrategy.deposit{value: wethToLend}(_crabToDeposit);

        return (wethToLend, usdcToBorrow);
    }

    function _getCrabVaultDetails() internal view returns (uint256, uint256) {
        VaultLib.Vault memory strategyVault = IController(address(controller)).vaults(crabV2.vaultId());

        return (strategyVault.collateralAmount, strategyVault.shortAmount);
    }

    function _calcBullToMint(uint256 _crabToDeposit) internal view returns (uint256) {
        if (IERC20(bullStrategy).totalSupply() == 0) {
            return _crabToDeposit;
        } else {
            uint256 share = _crabToDeposit.wdiv(bullStrategy.getCrabBalance().add(_crabToDeposit));
            return share.wmul(bullStrategy.totalSupply()).wdiv(uint256(1e18).sub(share));
        }
    }

    function _calcWPowerPerpAndCrabNeededForWithdraw(uint256 _bullAmount) internal view returns (uint256, uint256) {
        uint256 share = _bullAmount.wdiv(bullStrategy.totalSupply());
        uint256 crabToRedeem = share.wmul(bullStrategy.getCrabBalance());
        uint256 crabTotalSupply = IERC20(crabV2).totalSupply();
        (, uint256 squeethInCrab) = _getCrabVaultDetails();
        return (crabToRedeem.wmul(squeethInCrab).wdiv(crabTotalSupply), crabToRedeem);
    }

    function _calcUsdcNeededForWithdraw(uint256 _bullAmount) internal view returns (uint256) {
        uint256 share = _bullAmount.wdiv(bullStrategy.totalSupply());
        return share.wmul(IEulerDToken(dToken).balanceOf(address(bullStrategy)));
    }

    function _calcWethToWithdraw(uint256 _bullAmount) internal view returns (uint256) {
        return _bullAmount.wmul(IEulerEToken(eToken).balanceOfUnderlying(address(bullStrategy))).wdiv(
            bullStrategy.totalSupply()
        );
    }

    function _calcCollateralAndBorrowAmount(uint256 _crabToDeposit) internal view returns (uint256, uint256) {
        uint256 wethToLend;
        uint256 usdcToBorrow;
        if (IERC20(bullStrategy).totalSupply() == 0) {
            {
                uint256 ethUsdPrice = UniOracle._getTwap(
                    controller.ethQuoteCurrencyPool(), controller.weth(), controller.quoteCurrency(), TWAP, false
                );
                uint256 squeethEthPrice = UniOracle._getTwap(
                    controller.wPowerPerpPool(), controller.wPowerPerp(), controller.weth(), TWAP, false
                );
                (uint256 ethInCrab, uint256 squeethInCrab) = _getCrabVaultDetails();
                uint256 crabUsdPrice = (
                    ethInCrab.wmul(ethUsdPrice).sub(squeethInCrab.wmul(squeethEthPrice).wmul(ethUsdPrice))
                ).wdiv(crabV2.totalSupply());
                wethToLend = bullStrategy.TARGET_CR().wmul(_crabToDeposit).wmul(crabUsdPrice).wdiv(ethUsdPrice);
                usdcToBorrow = wethToLend.wmul(ethUsdPrice).wdiv(bullStrategy.TARGET_CR()).div(1e12);
            }
        } else {
            uint256 share = _crabToDeposit.wdiv(bullStrategy.getCrabBalance().add(_crabToDeposit));
            wethToLend = IEulerEToken(eToken).balanceOfUnderlying(address(bullStrategy)).wmul(share).wdiv(
                uint256(1e18).sub(share)
            );
            usdcToBorrow = IEulerDToken(dToken).balanceOf(address(bullStrategy)).wmul(share).wdiv(
                uint256(1e18).sub(share)
            ).div(1e12);
        }

        return (wethToLend, usdcToBorrow);
    }

    function _calcTotalEthDelta(uint256 _crabToDeposit) internal view returns (uint256) {
        uint256 ethUsdPrice = UniOracle._getTwap(
            controller.ethQuoteCurrencyPool(), controller.weth(), controller.quoteCurrency(), TWAP, false
        );
        uint256 squeethEthPrice =
            UniOracle._getTwap(controller.wPowerPerpPool(), controller.wPowerPerp(), controller.weth(), TWAP, false);
        (uint256 ethInCrab, uint256 squeethInCrab) = _getCrabVaultDetails();
        uint256 crabUsdPrice = (ethInCrab.wmul(ethUsdPrice).sub(squeethInCrab.wmul(squeethEthPrice).wmul(ethUsdPrice)))
            .wdiv(crabV2.totalSupply());
        uint256 totalEthDelta = (IEulerEToken(eToken).balanceOfUnderlying(address(bullStrategy)).wmul(ethUsdPrice)).wdiv(
            _crabToDeposit.wmul(crabUsdPrice).add(
                IEulerEToken(eToken).balanceOfUnderlying(address(bullStrategy)).wmul(ethUsdPrice)
            ).sub(IEulerDToken(dToken).balanceOf(address(bullStrategy)).mul(1e12))
        );

        return totalEthDelta;
    }
}