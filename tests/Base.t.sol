// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { StdCheats } from "@forge-std/StdCheats.sol";
import { console } from "@forge-std/console.sol";
import { ud, UD60x18 } from "@prb/math/UD60x18.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { UUPSProxy } from "../contracts/libraries/upgradability/UUPSProxy.sol";
import { Events } from "./utils/Events.sol";
import { Defaults } from "./utils/Defaults.sol";
import { Constants } from "./utils/Constants.sol";
import { Utils } from "./utils/Utils.sol";
import { Users } from "./utils/Types.sol";

// Mocks
import { MintableERC20WithPermit } from "./mocks/MintableERC20WithPermit.sol";

// interfaces
import { ILopoGlobals } from "../contracts/interfaces/ILopoGlobals.sol";
import { IReceivable } from "../contracts/interfaces/IReceivable.sol";
import { IPoolAddressesProvider } from "../contracts/interfaces/IPoolAddressesProvider.sol";
import { IPoolConfigurator } from "../contracts/interfaces/IPoolConfigurator.sol";
import { ILoanManager } from "../contracts/interfaces/ILoanManager.sol";
import { IWithdrawalManager } from "../contracts/interfaces/IWithdrawalManager.sol";
import { IPool } from "../contracts/interfaces/IPool.sol";

// storage
import { ReceivableStorage } from "../contracts/ReceivableStorage.sol";

// main contracts
import { LopoGlobals } from "../contracts/LopoGlobals.sol";
import { Receivable } from "../contracts/Receivable.sol";
import { PoolAddressesProvider } from "../contracts/PoolAddressesProvider.sol";
import { PoolConfigurator } from "../contracts/PoolConfigurator.sol";
import { LoanManager } from "../contracts/LoanManager.sol";
import { WithdrawalManager } from "../contracts/WithdrawalManager.sol";
import { Pool } from "../contracts/Pool.sol";

abstract contract Base_Test is StdCheats, Events, Constants, Utils {
    /*//////////////////////////////////////////////////////////////////////////
                                    VARIABLES
    //////////////////////////////////////////////////////////////////////////*/

    Users internal users;

    /*//////////////////////////////////////////////////////////////////////////
                                TEST CONTRACTS
    //////////////////////////////////////////////////////////////////////////*/

    MintableERC20WithPermit internal usdc;
    Defaults internal defaults;

    // Lopo Globals UUPS contract
    ILopoGlobals internal lopoGlobals;

    // Receivable UUPS contract
    IReceivable internal receivable;

    // Transparent proxy contracts
    IPoolAddressesProvider internal poolAddressesProvider; // Pool admin of the following contracts
    IPoolConfigurator internal poolConfigurator;
    IPool internal pool;
    ILoanManager internal loanManager;
    IWithdrawalManager internal withdrawalManager;

    /*//////////////////////////////////////////////////////////////////////////
                                SET-UP FUNCTION
    //////////////////////////////////////////////////////////////////////////*/

    function setUp() public virtual {
        usdc = new MintableERC20WithPermit("Circle USD", "USDC", ASSET_DECIMALS);

        // label contracts
        vm.label(address(usdc), "USDC");

        // create users for testing
        users = Users({
            governor: createUser("Governor"),
            poolAdmin: createUser("PoolAdmin"),
            seller: createUser("Seller"),
            buyer: createUser("Buyer"),
            caller: createUser("Caller"),
            staker: createAccount("Staker"),
            notStaker: createAccount("NotStaker"),
            receiver: createUser("Receiver"),
            notWhitelistedReceiver: createUser("notWhitelistedReceiver"),
            eve: createUser("eve")
        });

        // Deploy the defaults contract
        defaults = new Defaults();
        defaults.setAsset(usdc);
        defaults.setUsers(users);

        vm.warp({ timestamp: MAY_1_2023 });
        vm.startPrank(users.poolAdmin); // NOTE: Start prank so that change prank can work in the test suite
    }

    /*//////////////////////////////////////////////////////////////////////////
                                    HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Deploy all related lopo contracts
    function deployAndLabelCore() internal {
        changePrank(users.governor);
        receivable = deployReceivable();
        lopoGlobals = deployGlobals();

        poolAddressesProvider = deployPoolAddressesProvider(lopoGlobals);

        changePrank(users.poolAdmin);
        deployPoolConfigurator(poolAddressesProvider);
        deployWithdrawalManager(poolAddressesProvider);
        deployLoanManager(poolAddressesProvider);

        poolConfigurator = PoolConfigurator(poolAddressesProvider.getPoolConfigurator());
        loanManager = LoanManager(poolAddressesProvider.getLoanManager());
        withdrawalManager = WithdrawalManager(poolAddressesProvider.getWithdrawalManager());
        pool = Pool(poolConfigurator.pool());

        vm.label(address(receivable), "Receivable");
        vm.label(address(lopoGlobals), "LopoGlobals");
        vm.label(address(poolAddressesProvider), "PoolAddressesProvider");
        vm.label(address(poolConfigurator), "PoolConfigurator");
        vm.label(address(pool), "Pool");
        vm.label(address(loanManager), "LoanManager");
        vm.label(address(withdrawalManager), "WithdrawalManager");
    }

    /// @dev Deploy lopo Globals as an UUPS proxy
    function deployGlobals() internal returns (ILopoGlobals lopoGlobals_) {
        changePrank(users.governor);

        lopoGlobals_ = LopoGlobals(address(new UUPSProxy(address(new LopoGlobals()), "")));
        lopoGlobals_.initialize(users.governor);

        // Quick setup for globals
        lopoGlobals_.setValidPoolAdmin(users.poolAdmin, true);
        lopoGlobals_.setValidPoolAsset(address(usdc), true);
        lopoGlobals_.setValidCollateralAsset(address(receivable), true);
    }

    /// @dev Deploy receivable as an UUPS proxy
    function deployReceivable() internal returns (IReceivable receivable_) {
        changePrank(users.governor);

        // notice here we use Receivable instead of its interface IReceivable, since we want to call function
        receivable_ = Receivable(address(new UUPSProxy(address(new Receivable()), "")));
        receivable_.initialize(users.governor);
    }

    /// @dev Deploy pool addresses provider
    function deployPoolAddressesProvider(ILopoGlobals lopoGlobals_)
        internal
        returns (IPoolAddressesProvider poolAddressesProvider_)
    {
        poolAddressesProvider_ = new PoolAddressesProvider(users.poolAdmin, "BSOS Green Finance", address(lopoGlobals_));
    }

    /// @dev Deploy pool configurator
    function deployPoolConfigurator(IPoolAddressesProvider poolAddressesProvider_) internal {
        address poolConfigurator_ = address(new PoolConfigurator(poolAddressesProvider_));
        bytes memory params_ = abi.encodeWithSelector(
            IPoolConfigurator.initialize.selector,
            address(poolAddressesProvider_),
            users.poolAdmin,
            address(usdc),
            "BSOS Green Share",
            "BGS"
        );
        poolAddressesProvider_.setPoolConfiguratorImpl(poolConfigurator_, params_);
    }

    /// @dev Deploy withdrawal manager
    function deployWithdrawalManager(IPoolAddressesProvider poolAddressesProvider_) internal {
        address withdrawalManager_ = address(new WithdrawalManager(poolAddressesProvider_));

        bytes memory params = abi.encodeWithSelector(
            IWithdrawalManager.initialize.selector,
            address(poolAddressesProvider_),
            defaults.CYCLE_DURATION(),
            defaults.WINDOW_DURATION()
        );
        poolAddressesProvider_.setWithdrawalManagerImpl(withdrawalManager_, params);
    }

    /// @dev Deploy loan manager
    function deployLoanManager(IPoolAddressesProvider poolAddressesProvider_) internal {
        address loanManager_ = address(new LoanManager(poolAddressesProvider_));
        poolAddressesProvider_.setLoanManagerImpl(loanManager_);
    }

    /// @dev Generates a user, labels its address, and funds it with test assets.
    function createUser(string memory name_) internal returns (address payable user_) {
        StdCheats.Account memory account_ = createAccount(name_);
        user_ = payable(account_.addr);
    }

    /// @dev Generates a user with private key, labels its address, and funds it with test assets.
    function createAccount(string memory name_) internal returns (StdCheats.Account memory account_) {
        account_ = makeAccount(name_);
        vm.deal({ account: account_.addr, newBalance: 100 ether });
        deal({ token: address(usdc), to: account_.addr, give: 1_000_000e18 });
    }

    /// @dev Airdrops a specified amount of usdc to a recipient
    function airdropTo(address recipient_, uint256 amount_) internal {
        usdc.mint({ recipient_: recipient_, amount_: amount_ });
    }

    function printReceivableInfo(ReceivableStorage.ReceivableInfo memory RECVInfo) internal view {
        console.log("# ReceivableInfo ---------------------------------");
        console.log("-> buyer: %s", RECVInfo.buyer);
        console.log("-> seller: %s", RECVInfo.seller);
        // notice that faceAmount is UD60x18
        console.log("-> faceAmount: %s", RECVInfo.faceAmount.intoUint256());
        console.log("-> repaymentTimestamp: %s", RECVInfo.repaymentTimestamp);
        console.log("-> isValid: %s", RECVInfo.isValid);
        console.log("-> currencyCode: %s", RECVInfo.currencyCode);
        console.log(""); // for layout
    }

    function approveProtocol() internal {
        changePrank(users.caller);
        usdc.approve(address(pool), type(uint256).max);

        changePrank(users.receiver);
        usdc.approve(address(pool), type(uint256).max);

        changePrank(users.buyer);
        usdc.approve(address(loanManager), type(uint256).max);

        changePrank(users.poolAdmin);
        usdc.approve(address(poolConfigurator), type(uint256).max);
    }

    function callerDepositToReceiver(address caller, address receiver, uint256 amount) internal {
        changePrank(caller);
        pool.deposit(amount, receiver);
    }

    function callerMintToReceiver(address caller, address receiver, uint256 amount) internal {
        changePrank(caller);
        pool.mint(amount, receiver);
    }

    function createReceivable(uint256 faceAmount_) internal returns (uint256 receivablesTokenId_) {
        changePrank(users.buyer);
        receivablesTokenId_ =
            receivable.createReceivable(users.buyer, users.seller, ud(faceAmount_), block.timestamp + 30 days, 804);
    }

    function approveLoan(uint256 receivablesTokenId_, uint256 principalRequested_) internal returns (uint16 loanId_) {
        address collateralAsset_ = address(receivable);
        uint256 gracePeriod_ = 7 days;
        uint256[2] memory rates_ = [uint256(0.12e6), uint256(0.2e6)];
        uint256 fee_ = 0;

        changePrank(users.poolAdmin);
        loanId_ = loanManager.approveLoan(
            collateralAsset_, receivablesTokenId_, gracePeriod_, principalRequested_, rates_, fee_
        );
    }

    function fundLoan(uint16 loanId_) internal {
        changePrank(users.poolAdmin);
        loanManager.fundLoan(loanId_);
    }

    function configurePoolConfigurator() internal {
        changePrank(users.poolAdmin);
        poolConfigurator.setOpenToPublic(true);
        poolConfigurator.setPoolLimit(defaults.POOL_LIMIT());
        poolConfigurator.setValidLender(users.receiver, true);
        poolConfigurator.setValidLender(users.caller, true);
    }

    function configurePool() internal {
        changePrank(users.caller);
        // Caller is the singler depositor initially
        pool.deposit({ assets: defaults.POOL_SHARES(), receiver: users.receiver });
        // Now the total assets in the pool would be POOL_ASSETS
        airdropTo(address(pool), defaults.POOL_ASSETS() - usdc.balanceOf(address(pool)));
    }

    /*//////////////////////////////////////////////////////////////////////////
                                    CALL EXPECTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Expects a call to {IERC20.transfer}.
    function expectCallToTransfer(address to, uint256 amount) internal {
        vm.expectCall({ callee: address(usdc), data: abi.encodeCall(IERC20.transfer, (to, amount)) });
    }

    /// @dev Expects a call to {IERC20.transfer}.
    function expectCallToTransfer(IERC20 asset, address to, uint256 amount) internal {
        vm.expectCall({ callee: address(asset), data: abi.encodeCall(IERC20.transfer, (to, amount)) });
    }

    /// @dev Expects a call to {IERC20.transferFrom}.
    function expectCallToTransferFrom(address from, address to, uint256 amount) internal {
        vm.expectCall({ callee: address(usdc), data: abi.encodeCall(IERC20.transferFrom, (from, to, amount)) });
    }

    /// @dev Expects a call to {IERC20.transferFrom}.
    function expectCallToTransferFrom(IERC20 asset, address from, address to, uint256 amount) internal {
        vm.expectCall({ callee: address(asset), data: abi.encodeCall(IERC20.transferFrom, (from, to, amount)) });
    }
}