pragma solidity ^0.8.13;

// SPDX-License-Identifier: MIT

import "forge-std/console.sol";

import {TestUtils} from "../../utils/TestUtils.sol";

import {NodeRunner} from "../../../contracts/testing/liquid-staking/NodeRunner.sol";
import {RugContract} from "../../../contracts/testing/liquid-staking/RugContract.sol";
import {MockToken} from "../../../contracts/testing/liquid-staking/MockToken.sol";
import {MockLiquidStakingManager} from "../../../contracts/testing/liquid-staking/MockLiquidStakingManager.sol";
import {MockLiquidStakingManagerV2} from "../../../contracts/testing/liquid-staking/MockLiquidStakingManagerV2.sol";
import {OptionalGatekeeperFactory, OptionalHouseGatekeeper} from "../../../contracts/liquid-staking/OptionalGatekeeperFactory.sol";
import {UpgradeableBeacon} from "../../../contracts/proxy/UpgradeableBeacon.sol";
import {IDataStructures} from "@blockswaplab/stakehouse-contract-interfaces/contracts/interfaces/IDataStructures.sol";
import { IERC20 } from "@blockswaplab/stakehouse-solidity-api/contracts/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {MockSlotRegistry} from "../../../contracts/testing/stakehouse/MockSlotRegistry.sol";
import {MockSavETHRegistry} from "../../../contracts/testing/stakehouse/MockSavETHRegistry.sol";
import {LPToken} from "../../../contracts/liquid-staking/LPToken.sol";
import {StakingFundsVault} from "../../../contracts/liquid-staking/StakingFundsVault.sol";
import {Syndicate} from "../../../contracts/syndicate/Syndicate.sol";
import {MockStakeHouseUniverse} from "../../../contracts/testing/stakehouse/MockStakeHouseUniverse.sol";
import {MockBrandNFT} from "../../../contracts/testing/stakehouse/MockBrandNFT.sol";
import {MockBrandCentral} from "../../../contracts/testing/stakehouse/MockBrandCentral.sol";
import {MockRestrictedTickerRegistry} from "../../../contracts/testing/stakehouse/MockRestrictedTickerRegistry.sol";
import {StakeHouseRegistry} from "../../../contracts/testing/stakehouse/StakeHouseRegistry.sol";
import {MockAccountManager} from "../../../contracts/testing/stakehouse/MockAccountManager.sol";
import {SafeBox} from "../../../contracts/testing/stakehouse/SafeBox.sol";
import "../../../contracts/testing/liquid-staking/NonEOARepresentative.sol";
import { IBalanceReporter } from "@blockswaplab/stakehouse-contract-interfaces/contracts/interfaces/IBalanceReporter.sol";

contract LiquidStakingManagerTests is TestUtils {
    function setUp() public {
        vm.startPrank(accountFive); // this will mean it gets dETH initial supply
        factory = createMockLSDNFactory();
        vm.stopPrank();

        // Deploy 1 network and get default dependencies
        manager = deployNewLiquidStakingNetwork(factory, admin, false, "LSDN");

        savETHVault = getSavETHVaultFromManager(manager);
        stakingFundsVault = getStakingFundsVaultFromManager(manager);

        // make 'admin' the 'DAO'
        vm.prank(address(factory));
        manager.updateDAOAddress(admin);
    }

    function testDeployHouseWithCommission() public {
        uint256 commission = 15_00000;
        MockLiquidStakingManager man = deployNewLiquidStakingNetworkWithCommission(
                factory,
                commission,
                admin,
                false,
                "COM"
            );

        // make 'admin' the 'DAO'
        vm.prank(address(factory));
        man.updateDAOAddress(admin);

        registerSingleBLSPubKey(accountOne, blsPubKeyOne, accountFour, man);

        vm.deal(accountOne, 32 ether);
        vm.startPrank(accountOne);
        man.savETHVault().depositETHForStaking{value: 24 ether}(
            blsPubKeyOne,
            24 ether
        );
        man.stakingFundsVault().depositETHForStaking{value: 4 ether}(
            blsPubKeyOne,
            4 ether
        );
        vm.stopPrank();

        stakeAndMintDerivativesSingleKey(blsPubKeyOne, man);

        vm.deal(address(man.syndicate()), 100 ether);
        vm.roll(block.number + 200);

        uint256 accountOneBalBefore = accountOne.balance;
        vm.startPrank(accountOne);
        man.claimRewardsAsNodeRunner(
            accountOne,
            getBytesArrayFromBytes(blsPubKeyOne)
        );
        vm.stopPrank();

        uint256 nodeRewards = (100 ether / 2);
        assertEq(
            accountOne.balance - accountOneBalBefore,
            nodeRewards - ((nodeRewards * 15) / 100)
        );
    }

    function testDeployLSDAndConfigureHouse() public {
        // Create house
        mockDerivativeMint(blsPubKeyOne);

        // Deploy a new LSD with gatekeeping
        MockLiquidStakingManager man = deployNewLiquidStakingNetwork(
            factory,
            admin,
            false,
            "HOUSE"
        );

        assert(man.stakehouse() == address(0));
        assertEq(man.numberOfKnots(), 0);

        // make 'admin' the 'DAO'
        vm.prank(address(factory));
        man.updateDAOAddress(admin);

        vm.prank(admin);
        man.configureStakeHouse(blsPubKeyOne);

        assert(man.stakehouse() != address(0));
        assertEq(man.numberOfKnots(), 1);
    }

    // https://code4rena.com/reports/2022-11-stakehouse/#m-24-node-runner-who-is-already-known-to-be-malicious-cannot-be-banned-before-corresponding-smart-wallet-is-created
    function testMaliciousNodeRunnerCannotBeBannedBeforeCorrespondingSmartWalletIsCreated()
        public
    {
        // Simulate a situation where accountOne is known to be malicious already.
        // accountOne is not banned at this moment.
        assertEq(manager.bannedNodeRunners(accountOne), false);

        vm.startPrank(admin);
        manager.manageNodeRunnerSmartWallet(accountOne, address(0), true);
        vm.stopPrank();

        assertEq(manager.bannedNodeRunners(accountOne), true);

        // Calling the rotateNodeRunnerOfSmartWallet function is the only way to ban accountOne;
        //   however, calling it reverts because accountOne has not called the registerBLSPublicKeys function to create a smart wallet yet.
        // This means that it is not possible to prevent accountOne from interacting with the protocol until her or his smart wallet is created.
        //vm.prank(admin);
        //vm.expectRevert("Wallet does not exist");
        //manager.rotateNodeRunnerOfSmartWallet(accountOne, accountTwo, true);

        // Node runner was banned ahead of time and now they cannot register a key or ever get a smart wallet
        vm.expectRevert(bytes4(keccak256("NodeRunnerNotPermitted()")));
        registerSingleBLSPubKey(accountOne, blsPubKeyOne, accountFour);
    }

    // https://code4rena.com/reports/2022-11-stakehouse/#m-23-calling-updatenoderunnerwhiteliststatus-function-always-reverts
    function testCallingUpdateNodeRunnerWhitelistStatusFunctionAlwaysReverts()
        public
    {
        vm.startPrank(admin);

        address[] memory nodeRunners = new address[](1);
        nodeRunners[0] = accountOne;
        manager.updateNodeRunnerWhitelistStatus(nodeRunners, true);
        assertEq(manager.isNodeRunnerWhitelisted(accountOne), true);

        nodeRunners[0] = accountTwo;
        manager.updateNodeRunnerWhitelistStatus(nodeRunners, false);
        vm.stopPrank();
        assertEq(manager.isNodeRunnerWhitelisted(accountTwo), false);
    }

    // https://code4rena.com/reports/2022-11-stakehouse/#m-23-calling-updatenoderunnerwhiteliststatus-function-always-reverts
    function testDeployLSDWithGatekeeper() public {
        // Deploy a new LSD with gatekeeping
        MockLiquidStakingManager man = deployNewLiquidStakingNetwork(
            factory,
            admin,
            true,
            "CLOSE"
        );

        // make 'admin' the 'DAO'
        vm.prank(address(factory));
        man.updateDAOAddress(admin);

        // Check keeper was deployed
        assert(address(man.gatekeeper()) != address(0));
        assert(man.enableWhitelisting());
        assertEq(man.dao(), admin);

        // create house
        address nodeRunner = accountTwo;
        vm.deal(nodeRunner, 100 ether);

        IERC20 dETHToken = savETHVault.dETHToken();
        vm.startPrank(accountFive);
        dETHToken.transfer(address(savETHVault.saveETHRegistry()), 96 ether);
        vm.stopPrank();

        address[] memory nodeRunners = new address[](1);
        nodeRunners[0] = nodeRunner;
        vm.prank(admin);
        man.updateNodeRunnerWhitelistStatus(nodeRunners, true);

        registerSingleBLSPubKey(nodeRunner, blsPubKeyOne, accountFour, man);

        vm.deal(accountOne, 32 ether);
        vm.startPrank(accountOne);
        man.savETHVault().depositETHForStaking{value: 24 ether}(
            blsPubKeyOne,
            24 ether
        );
        man.stakingFundsVault().depositETHForStaking{value: 4 ether}(
            blsPubKeyOne,
            4 ether
        );
        vm.stopPrank();

        stakeAndMintDerivativesSingleKey(blsPubKeyOne, man);

        assert(man.stakehouse() != address(0));
        assert(StakeHouseRegistry(man.stakehouse()).keeper() != address(0));
        assertEq(man.gatekeeper().isMemberPermitted(blsPubKeyOne), true);

        // Disable house keeper
        vm.startPrank(admin);
        man.toggleHouseGatekeeper(false);
        vm.stopPrank();
        assert(StakeHouseRegistry(man.stakehouse()).keeper() == address(0));
    }

    // https://code4rena.com/reports/2022-11-stakehouse/#m-10--incorrect-implementation-of-the-ethpoollpfactorysolrotatelptokens-let-user-stakes-eth-more-than-maxstakingamountpervalidator-in-stakingfundsvault-and-dos-the-stake-function-in-liquidstakingmanager
    function test_rotateLP_Exceed_maxStakingAmountPerValidator_POC() public {
        address user = vm.addr(21312);
        bytes memory blsPubKeyOne = fromHex(
            "94fdc9a61a34eb6a034e343f20732456443a2ed6668ede04677adc1e15d2a24500a3e05cf7ad3dc3b2f3cc13fdc12af5"
        );
        bytes memory blsPubKeyTwo = fromHex(
            "9AAdc9a61a34eb6a034e343f20732456443a2ed6668ede04677adc1e15d2a24500a3e05cf7ad3dc3b2f3cc13fdc12af5"
        );
        bytes[] memory publicKeys = new bytes[](2);
        publicKeys[0] = blsPubKeyOne;
        publicKeys[1] = blsPubKeyTwo;
        bytes[] memory signature = new bytes[](2);
        signature[0] = "signature";
        signature[1] = "signature";
        // user spends 8 ether and register two keys to become the public operator
        vm.prank(user);
        vm.deal(user, 8 ether);
        manager.registerBLSPublicKeys{value: 8 ether}(
            publicKeys,
            signature,
            user
        );
        // active two keys
        MockAccountManager(factory.accountMan()).setLifecycleStatus(
            blsPubKeyOne,
            1
        );
        MockAccountManager(factory.accountMan()).setLifecycleStatus(
            blsPubKeyTwo,
            1
        );
        // deposit 4 ETH for public key one and public key two
        StakingFundsVault stakingFundsVault = manager.stakingFundsVault();
        stakingFundsVault.depositETHForStaking{value: 4 ether}(
            blsPubKeyOne,
            4 ether
        );
        stakingFundsVault.depositETHForStaking{value: 4 ether}(
            blsPubKeyTwo,
            4 ether
        );
        // to bypass the error: "Liquidity is still fresh"
        vm.warp(1 days);
        // rotate staking amount from public key one to public key two
        // LP total supply for public key two exceed 4 ETHER
        LPToken LPTokenForPubKeyOne = manager
            .stakingFundsVault()
            .lpTokenForKnot(blsPubKeyOne);
        LPToken LPTokenForPubKeyTwo = manager
            .stakingFundsVault()
            .lpTokenForKnot(blsPubKeyTwo);
        vm.expectRevert("Not enough mintable tokens");
        stakingFundsVault.rotateLPTokens(
            LPTokenForPubKeyOne,
            LPTokenForPubKeyTwo,
            4 ether
        );
        uint256 totalSupply = LPTokenForPubKeyTwo.totalSupply();
        console.log("total supply of the Staking fund LP exists 4 ETHER.");
        console.log(totalSupply);
    }

    // https://code4rena.com/reports/2022-11-stakehouse/#m-08-dao-admin-in-liquidstakingmanagersol-can-rug-the-registered-node-operator-by-stealing-their-fund-in-the-smart-wallet-via-arbitrary-execution
    function testDaoRugFund_Pull_ETH_POC() public {
        address user = vm.addr(21312);
        bytes[] memory publicKeys = new bytes[](1);
        publicKeys[0] = "publicKeys";
        bytes[] memory signature = new bytes[](1);
        signature[0] = "signature";
        RugContract rug = new RugContract();
        // user spends 4 ehter and register the key to become the public operator
        vm.prank(user);
        vm.deal(user, 4 ether);
        manager.registerBLSPublicKeys{value: 4 ether}(
            publicKeys,
            signature,
            user
        );
        address wallet = manager.smartWalletOfNodeRunner(user);
        console.log("wallet ETH balance for user after registering");
        console.log(wallet.balance);
        // dao admin rug the user by withdraw the ETH via arbitrary execution.
        vm.prank(admin);
        bytes memory data = abi.encodeWithSelector(
            RugContract.receiveFund.selector,
            ""
        );
        // Unsafe function no longer allowed
        //vm.expectRevert(bytes4(keccak256("InvalidAmount()")));
        //manager.executeAsSmartWallet(user, address(rug), data, 4 ether);
        console.log("wallet ETH balance for user after DAO admin rugging");
        console.log(wallet.balance);
    }

    // https://code4rena.com/reports/2022-11-stakehouse/#m-08-dao-admin-in-liquidstakingmanagersol-can-rug-the-registered-node-operator-by-stealing-their-fund-in-the-smart-wallet-via-arbitrary-execution
    function testDaoRugFund_Pull_ERC20_Token_POC() public {
        address user = vm.addr(21312);
        bytes[] memory publicKeys = new bytes[](1);
        publicKeys[0] = "publicKeys";
        bytes[] memory signature = new bytes[](1);
        signature[0] = "signature";
        RugContract rug = new RugContract();
        vm.prank(user);
        vm.deal(user, 4 ether);
        manager.registerBLSPublicKeys{value: 4 ether}(
            publicKeys,
            signature,
            user
        );
        address wallet = manager.smartWalletOfNodeRunner(user);
        MockToken token = new MockToken();
        token.transfer(wallet, 100 ether);
        console.log("wallet ERC20 token balance for user after registering");
        console.log(token.balanceOf(wallet));
        vm.prank(admin);
        bytes memory data = abi.encodeWithSelector(
            IERC20.transfer.selector,
            address(rug),
            100 ether
        );
        // Unsafe function no longer allowed
        //vm.expectRevert(bytes4(keccak256("OnlyCIP()")));
        //manager.executeAsSmartWallet(user, address(token), data, 0);
        console.log("wallet ERC20 token balance for dao rugging");
        console.log(token.balanceOf(wallet));
    }

    function testCannotDeployLSDNIfTickerIsTaken() public {
        mockDerivativeMint(blsPubKeyOne);

        vm.expectRevert(bytes4(keccak256("TickerAlreadyTaken()")));
        factory.deployNewMockLiquidStakingDerivativeNetwork(
            admin,
            false,
            "LSDN"
        );
    }

    function testCannotDeployLSDNIfTickerIsRestricted() public {
        MockBrandNFT brand = MockBrandNFT(factory.brand());
        MockBrandCentral bc = MockBrandCentral(brand.brandCentral());
        MockRestrictedTickerRegistry registry = MockRestrictedTickerRegistry(
            bc.claimAuction()
        );
        registry.setIsRestricted("vince", true);

        vm.expectRevert(bytes4(keccak256("TickerAlreadyTaken()")));
        factory.deployNewMockLiquidStakingDerivativeNetwork(
            admin,
            false,
            "VINCE"
        );
    }

    // https://code4rena.com/reports/2022-11-stakehouse/#h-05-reentrancy-in-liquidstakingmanagersolwithdrawethforknow-leads-to-loss-of-fund-from-smart-wallet
    function testBypassIsContractCheck_POC() public {
        NonEOARepresentative pass = new NonEOARepresentative{value: 8 ether}(
            address(manager)
        );
        address wallet = manager.smartWalletOfNodeRunner(address(pass));
        address reprenstative = manager.smartWalletRepresentative(wallet);
        console.log("smart contract registered as a EOA representative");
        console.log(address(reprenstative) == address(pass));
        // to set the public key state to IDataStructures.LifecycleStatus.INITIALS_REGISTERED
        MockAccountManager(factory.accountMan()).setLifecycleStatus(
            "publicKeys1",
            1
        );
        // expected to withdraw 4 ETHER, but reentrancy allows withdrawing 8 ETHER
        vm.expectRevert("Failed to execute"); // We now revert
        pass.withdraw("publicKeys1");
        console.log(
            "balance after the withdraw, expected 4 ETH, but has 0 ETH because of failed reentrancy"
        );
        console.log(address(pass).balance);
    }

    // https://code4rena.com/reports/2022-11-stakehouse/#h-11-protocol-insolvent---permanent-freeze-of-funds
    function testLockStakersFunds() public {
        uint256 startAmount = 8 ether;
        // Create NodeRunner. Constructor registers two BLS Keys
        address nodeRunner = address(
            new NodeRunner{value: startAmount}(
                manager,
                blsPubKeyOne,
                blsPubKeyTwo,
                address(this)
            )
        );

        // Simulate state transitions in lifecycle status to initials registered (value of 1)
        MockAccountManager(factory.accountMan()).setLifecycleStatus(
            blsPubKeyOne,
            1
        );
        // savETHUser, feesAndMevUser funds used to deposit into validator BLS key #1
        address feesAndMevUser = accountTwo;
        vm.deal(feesAndMevUser, 4 ether);
        address savETHUser = accountThree;
        vm.deal(savETHUser, 24 ether);

        // deposit savETHUser, feesAndMevUser funds for validator #1
        depositIntoDefaultSavETHVault(savETHUser, blsPubKeyOne, 24 ether);
        depositIntoDefaultStakingFundsVault(
            feesAndMevUser,
            blsPubKeyOne,
            4 ether
        );
        // withdraw ETH for first BLS key and reenter
        // This will perform a cross-function reentracy to call stake
        vm.startPrank(nodeRunner);
        vm.expectRevert("Failed to execute");
        manager.withdrawETHForKnot(nodeRunner, blsPubKeyOne);
        // Simulate state transitions in lifecycle status to ETH deposited (value of 2)
        // In real deployment, when stake is called TransactionRouter.registerValidator is called to change the state to DEPOSIT_COMPLETE
        MockAccountManager(factory.accountMan()).setLifecycleStatus(
            blsPubKeyOne,
            2
        );
        vm.stopPrank();

        // Rest of the test no longer works
        //        // Validate mintDerivatives reverts because of banned public key
        //        (,IDataStructures.ETH2DataReport[] memory reports) = getFakeBalanceReport();
        //        (,IDataStructures.EIP712Signature[] memory sigs) = getFakeEIP712Signature();
        //        vm.expectRevert("BLS public key is banned or not a part of LSD network");
        //        manager.mintDerivatives(
        //            getBytesArrayFromBytes(blsPubKeyOne),
        //            reports,
        //            sigs
        //        );
        //        // Validate depositor cannot burn LP tokens
        //        vm.startPrank(savETHUser);
        //        vm.expectRevert("Cannot burn LP tokens");
        //        savETHVault.burnLPTokensByBLS(getBytesArrayFromBytes(blsPubKeyOne), getUint256ArrayFromValues(24 ether));
        //        vm.stopPrank();
    }

    function mockDerivativeMint(bytes memory _blsKey) internal {
        address nodeRunner = accountTwo;
        vm.deal(nodeRunner, 100 ether);

        IERC20 dETHToken = savETHVault.dETHToken();
        vm.startPrank(accountFive);
        dETHToken.transfer(address(savETHVault.saveETHRegistry()), 96 ether);
        vm.stopPrank();

        registerSingleBLSPubKey(nodeRunner, _blsKey, accountFour);

        vm.deal(accountOne, 32 ether);
        vm.startPrank(accountOne);
        savETHVault.depositETHForStaking{value: 24 ether}(_blsKey, 24 ether);
        stakingFundsVault.depositETHForStaking{value: 4 ether}(
            _blsKey,
            4 ether
        );
        vm.stopPrank();

        stakeAndMintDerivativesSingleKey(_blsKey);
    }

    function testDeployingAndUsingGatekeeperFactory() public {
        mockDerivativeMint(blsPubKeyOne);

        OptionalGatekeeperFactory gatekeeperFactory = new OptionalGatekeeperFactory();
        OptionalHouseGatekeeper keeper = gatekeeperFactory.deploy(
            address(manager)
        );

        assertEq(keeper.isMemberPermitted(blsPubKeyOne), true);
        assertEq(keeper.isMemberPermitted(blsPubKeyTwo), false);
    }

    function testInitialization() public {
        assertEq(manager.dao(), admin);

        assertEq(manager.brand(), factory.brand());

        assertEq(
            address(manager.syndicateFactory()),
            factory.syndicateFactory()
        );

        assertEq(
            address(manager.smartWalletFactory()),
            factory.smartWalletFactory()
        );

        assertEq(manager.stakehouseTicker(), "LSDN");

        assertEq(address(manager.factory()), address(factory));

        assertEq(address(manager.savETHVault()), address(savETHVault));

        assertEq(
            address(manager.stakingFundsVault()),
            address(stakingFundsVault)
        );
    }

    function testUpdateDAOAddress() public {
        assertEq(manager.dao(), admin);

        vm.startPrank(admin);
        manager.updateDAOAddress(accountOne);
        vm.stopPrank();

        assertEq(manager.dao(), accountOne);
    }

    function testRemoveDAOAccess() public {
        vm.startPrank(admin);
        manager.updateDAOAddress(address(0));
        vm.stopPrank();

        vm.expectRevert(bytes4(keccak256("OnlyDAO()")));
        vm.prank(admin);
        manager.updateDAORevenueCommission(10);
    }

    function testUpdateDAOAddressRevert() public {
        vm.expectRevert(bytes4(keccak256("OnlyDAO()")));
        manager.updateDAOAddress(accountOne);
    }

    function testUpdateDAORevenueCommission() public {
        assertEq(manager.daoCommissionPercentage(), 0);

        vm.startPrank(admin);
        manager.updateDAORevenueCommission(10);
        vm.stopPrank();

        assertEq(manager.daoCommissionPercentage(), 10);
    }

    // https://code4rena.com/reports/2022-11-stakehouse/#m-18-node-runners-can-lose-all-their-stake-rewards-due-to-how-the-dao-commissions-can-be-set-to-a-100
    function testUpdateDAORevenueCommissionRevert() public {
        vm.expectRevert(bytes4(keccak256("OnlyDAO()")));
        manager.updateDAORevenueCommission(10);

        vm.startPrank(admin);
        vm.expectRevert(bytes4(keccak256("InvalidCommission()")));
        manager.updateDAORevenueCommission(50_00000 + 1);
        vm.stopPrank();
    }

    function testUpdateTicker() public {
        assertEq(manager.stakehouseTicker(), "LSDN");

        vm.startPrank(admin);
        manager.updateTicker("LSDNA");
        vm.stopPrank();

        assertEq(manager.stakehouseTicker(), "LSDNA");
    }

    function testUpdateTickerReverts() public {
        vm.expectRevert(bytes4(keccak256("OnlyDAO()")));
        manager.updateTicker("LSDNA");

        vm.startPrank(admin);
        vm.expectRevert(bytes4(keccak256("InvalidTickerLength()")));
        manager.updateTicker("LS");
        vm.expectRevert(bytes4(keccak256("InvalidTickerLength()")));
        manager.updateTicker("LSDNET");
        vm.stopPrank();

        mockDerivativeMint(blsPubKeyOne);

        vm.startPrank(admin);
        vm.expectRevert(bytes4(keccak256("HouseAlreadyCreated()")));
        manager.updateTicker("LSDNA");
        vm.stopPrank();
    }

    function testRegisterKnotsToSyndicate() public {
        mockDerivativeMint(blsPubKeyOne);

        vm.expectRevert(bytes4(keccak256("OnlyDAO()")));
        manager.registerKnotsToSyndicate(getBytesArrayFromBytes(blsPubKeyTwo));

        mockDerivativeMint(blsPubKeyTwo);

        vm.expectRevert(bytes4(keccak256("KnotIsAlreadyRegistered()")));
        vm.prank(admin);
        manager.registerKnotsToSyndicate(getBytesArrayFromBytes(blsPubKeyTwo));

        assertEq(
            Syndicate(payable(manager.syndicate())).isKnotRegistered(
                blsPubKeyTwo
            ),
            true
        );
    }

    function testDeRegisterKnotFromSyndicate() public {
        mockDerivativeMint(blsPubKeyOne);

        vm.expectRevert(bytes4(keccak256("OnlyDAO()")));
        manager.deRegisterKnotFromSyndicate(
            getBytesArrayFromBytes(blsPubKeyTwo)
        );

        mockDerivativeMint(blsPubKeyTwo);

        vm.roll(block.number + 1 + 600);
        Syndicate(payable(manager.syndicate())).activateProposers();

        vm.prank(admin);
        manager.deRegisterKnotFromSyndicate(
            getBytesArrayFromBytes(blsPubKeyTwo)
        );

        assertEq(
            Syndicate(payable(manager.syndicate())).isNoLongerPartOfSyndicate(
                blsPubKeyTwo
            ),
            true
        );
    }

    // https://code4rena.com/reports/2022-11-stakehouse/#m-26-compromised-or-malicious-dao-can-restrict-actions-of-node-runners-who-are-not-malicious
    function testCompromisedDaoCanRestrictActionsOfNodeRunnersWhoAreNotMalicious()
        public
    {
        uint256 nodeStakeAmount = 4 ether;
        address nodeRunner = accountOne;
        vm.deal(nodeRunner, nodeStakeAmount);
        address eoaRepresentative = accountTwo;
        vm.startPrank(nodeRunner);
        manager.registerBLSPublicKeys{value: nodeStakeAmount}(
            getBytesArrayFromBytes(blsPubKeyOne),
            getBytesArrayFromBytes(blsPubKeyOne),
            eoaRepresentative
        );
        vm.stopPrank();
        // Simulate a situation where admin, who is the dao at this moment, is compromised.
        // Although nodeRunner is not malicious,
        //   the compromised admin can call the rotateNodeRunnerOfSmartWallet function to assign nodeRunner's smart wallet to a colluded party.
        vm.prank(admin);
        vm.expectRevert(bytes4(keccak256("InvalidAmount()")));
        manager.manageNodeRunnerSmartWallet(nodeRunner, accountThree, true);
        // nodeRunner is blocked from other interactions with the protocol since it is now banned unfairly
        assertEq(manager.bannedNodeRunners(accountOne), false);
        // for example, nodeRunner is no longer able to call the withdrawETHForKnot function
        //vm.prank(nodeRunner);
        //vm.expectRevert("Not the node runner for the smart wallet");
        //manager.withdrawETHForKnot(nodeRunner, blsPubKeyOne);
    }

    function testUpdateBrandInfo() public {
        mockDerivativeMint(blsPubKeyOne);

        MockBrandNFT brand = MockBrandNFT(manager.brand());
        uint256 tokenId = MockBrandNFT(brand).lowercaseBrandTickerToTokenId(
            MockBrandNFT(brand).toLowerCase("LSDN")
        );

        vm.expectRevert(bytes4(keccak256("OnlyDAO()")));
        manager.updateBrandInfo(tokenId, "description", "image URI");

        vm.prank(admin);
        manager.updateBrandInfo(tokenId, "description", "image URI");

        assertEq(brand.nftDescription(tokenId), "description");
        assertEq(brand.nftImageURI(tokenId), "image URI");
    }

    function testUpdateNodeRunnerWhitelistStatus() public {
        address nodeRunner = accountTwo;

        assertEq(manager.isNodeRunnerWhitelisted(nodeRunner), false);

        vm.expectRevert(bytes4(keccak256("OnlyDAO()")));
        manager.updateNodeRunnerWhitelistStatus(
            getAddressArrayFromValues(nodeRunner),
            true
        );

        vm.prank(admin);
        manager.updateNodeRunnerWhitelistStatus(
            getAddressArrayFromValues(nodeRunner),
            true
        );

        assertEq(manager.isNodeRunnerWhitelisted(nodeRunner), true);

        vm.prank(admin);
        manager.updateNodeRunnerWhitelistStatus(
            getAddressArrayFromValues(nodeRunner),
            false
        );
        assertEq(manager.isNodeRunnerWhitelisted(nodeRunner), false);
    }

    function testRotateEOARepresentative() public {
        address nodeRunner = accountTwo;
        vm.deal(nodeRunner, 4 ether);
        vm.startPrank(nodeRunner);
        manager.registerBLSPublicKeys{value: 4 ether}(
            getBytesArrayFromBytes(blsPubKeyOne),
            getBytesArrayFromBytes(blsPubKeyOne),
            accountFive
        );
        vm.stopPrank();

        address smartWallet = manager.smartWalletOfNodeRunner(nodeRunner);
        assertEq(manager.smartWalletRepresentative(smartWallet), accountFive);

        vm.expectRevert(bytes4(keccak256("OnlyEOA()")));
        manager.rotateEOARepresentative(address(savETHVault));

        vm.expectRevert(bytes4(keccak256("ZeroAddress()")));
        manager.rotateEOARepresentative(address(0));

        vm.expectRevert(bytes4(keccak256("OnlyNodeRunner()")));
        manager.rotateEOARepresentative(accountFour);

        vm.prank(nodeRunner);
        manager.rotateEOARepresentative(accountFour);

        assertEq(manager.smartWalletRepresentative(smartWallet), accountFour);
    }

    function testWithdrawETHForKnot() public {
        address nodeRunner = accountTwo;
        vm.deal(nodeRunner, 100 ether);

        vm.expectRevert(bytes4(keccak256("ZeroAddress()")));
        manager.withdrawETHForKnot(address(0), blsPubKeyOne);

        vm.expectRevert(bytes4(keccak256("BLSKeyNotRegistered()")));
        manager.withdrawETHForKnot(nodeRunner, blsPubKeyOne);

        registerSingleBLSPubKey(nodeRunner, blsPubKeyOne, accountFour);
        address nodeRunnerSmartWallet = manager.smartWalletOfNodeRunner(
            nodeRunner
        );
        assertEq(nodeRunnerSmartWallet.balance, 4 ether);

        vm.expectRevert(bytes4(keccak256("OnlyNodeRunner()")));
        manager.withdrawETHForKnot(nodeRunner, blsPubKeyOne);

        MockAccountManager(manager.accountMan()).setLifecycleStatus(
            blsPubKeyOne,
            2
        );
        vm.expectRevert(bytes4(keccak256("InitialsNotRegistered()")));
        vm.prank(nodeRunner);
        manager.withdrawETHForKnot(nodeRunner, blsPubKeyOne);

        MockAccountManager(manager.accountMan()).setLifecycleStatus(
            blsPubKeyOne,
            1
        );
        vm.prank(nodeRunner);
        manager.withdrawETHForKnot(nodeRunner, blsPubKeyOne);
    }

    function testCanUpgradeLSM() public {
        MockLiquidStakingManagerV2 man = new MockLiquidStakingManagerV2();
        UpgradeableBeacon beacon = UpgradeableBeacon(
            factory.liquidStakingManagerBeacon()
        );

        // Reverts if not owner
        vm.expectRevert("Ownable: caller is not the owner");
        beacon.updateImplementation(address(man));

        vm.startPrank(accountFive);
        beacon.updateImplementation(address(man));
        vm.stopPrank();
        assertEq(
            MockLiquidStakingManagerV2(payable(address(manager))).sing(),
            true
        );
    }

    // https://code4rena.com/reports/2022-11-stakehouse/#m-27-rotatenoderunnerofsmartwallet-is-vulnerable-to-a-frontrun-attack
    function testChangeNodeRunnerWithoutBan() public {
        address nodeRunner = accountTwo;
        address newNodeRunner = accountThree;

        vm.expectRevert(bytes4(keccak256("OnlyDAO()")));
        manager.manageNodeRunnerSmartWallet(nodeRunner, newNodeRunner, true);

        vm.expectRevert(bytes4(keccak256("ZeroAddress()")));
        vm.prank(admin);
        manager.manageNodeRunnerSmartWallet(nodeRunner, newNodeRunner, true);

        vm.deal(nodeRunner, 100 ether);
        registerSingleBLSPubKey(nodeRunner, blsPubKeyOne, accountFour);
        address nodeRunnerSmartWallet = manager.smartWalletOfNodeRunner(
            nodeRunner
        );

        vm.startPrank(nodeRunner);
        manager.withdrawETHForKnot(nodeRunner, blsPubKeyOne);
        vm.stopPrank();

        vm.prank(admin);
        manager.manageNodeRunnerSmartWallet(nodeRunner, newNodeRunner, false);
        assertEq(
            manager.smartWalletOfNodeRunner(newNodeRunner),
            nodeRunnerSmartWallet
        );
        assertEq(
            manager.nodeRunnerOfSmartWallet(nodeRunnerSmartWallet),
            newNodeRunner
        );
        assertEq(manager.bannedNodeRunners(nodeRunner), false);
    }

    // https://code4rena.com/reports/2022-11-stakehouse/#m-11-banned-bls-public-keys-can-still-be-registered
    function testChangeNodeRunnerWithBan() public {
        address nodeRunner = accountTwo;
        vm.deal(nodeRunner, 100 ether);
        registerSingleBLSPubKey(nodeRunner, blsPubKeyOne, accountFour);
        address nodeRunnerSmartWallet = manager.smartWalletOfNodeRunner(
            nodeRunner
        );
        address newNodeRunner = accountThree;

        vm.startPrank(nodeRunner);
        manager.withdrawETHForKnot(nodeRunner, blsPubKeyOne);
        vm.stopPrank();

        vm.prank(admin);
        manager.manageNodeRunnerSmartWallet(nodeRunner, newNodeRunner, true);
        assertEq(
            manager.smartWalletOfNodeRunner(newNodeRunner),
            nodeRunnerSmartWallet
        );
        assertEq(
            manager.nodeRunnerOfSmartWallet(nodeRunnerSmartWallet),
            newNodeRunner
        );
        assertEq(manager.bannedNodeRunners(nodeRunner), true);

        // Make sure that the banned node runner cannot register a bls key
        vm.expectRevert(bytes4(keccak256("NodeRunnerNotPermitted()")));
        registerSingleBLSPubKey(nodeRunner, blsPubKeyTwo, accountFour);

        // Cannot register same key again
        vm.expectRevert(bytes4(keccak256("BLSKeyAlreadyRegistered()")));
        registerSingleBLSPubKey(newNodeRunner, blsPubKeyOne, accountFour);

        // New node runner can register but will not be able to stake after being banned
        registerSingleBLSPubKey(newNodeRunner, blsPubKeyThree, accountFour);

        vm.prank(admin);
        manager.manageNodeRunnerSmartWallet(newNodeRunner, address(0), true);

        vm.expectRevert(bytes4(keccak256("NodeRunnerNotPermitted()")));
        stakeSingleBlsPubKey(blsPubKeyThree);
    }

    // https://code4rena.com/reports/2022-11-stakehouse/#m-22-eth-sent-when-calling-executeassmartwallet-function-can-be-lost
    function testETHSentWhenCallingExecuteAsSmartWalletFunctionCanBeLost()
        public
    {
        uint256 nodeStakeAmount = 4 ether;
        address nodeRunner = accountOne;
        vm.deal(nodeRunner, nodeStakeAmount);
        address eoaRepresentative = accountTwo;
        vm.prank(nodeRunner);
        manager.registerBLSPublicKeys{value: nodeStakeAmount}(
            getBytesArrayFromBytes(blsPubKeyOne),
            getBytesArrayFromBytes(blsPubKeyOne),
            eoaRepresentative
        );
        // Before the executeAsSmartWallet function is called, the manager contract owns 0 ETH,
        //   and nodeRunner's smart wallet owns 4 ETH.
        assertEq(address(manager).balance, 0);
        assertEq(manager.smartWalletOfNodeRunner(nodeRunner).balance, 4 ether);
        uint256 amount = 1.5 ether;
        vm.deal(admin, amount);
        vm.startPrank(admin);
        // Unsafe function no longer allowed
        //vm.expectRevert(bytes4(keccak256("OnlyCIP()")));
        //manager.executeAsSmartWallet{value: amount}(
        //    nodeRunner,
        //    address(this),
        //    bytes(""),
        //    amount
        //);
        vm.stopPrank();
        // Although admin attempts to send the 1.5 ETH through calling the executeAsSmartWallet function,
        //   the sent 1.5 ETH was not transferred to nodeRunner's smart wallet but is locked in the manager contract instead.
        // Update this is zero since user has to attach value but also we restrict what can be called
        assertEq(address(manager).balance, 0);
        // Because nodeRunner's smart wallet owns more than 1.5 ETH, 1.5 ETH of this smart wallet's ETH balance is actually sent to address(this).
        // Update - smart wallet balance still 4
        assertEq(manager.smartWalletOfNodeRunner(nodeRunner).balance, 4 ether);
    }

    function testRecoverSigningKeyWhenNotRegistered() public {
        address nodeRunner = accountOne;
        vm.expectRevert(bytes4(keccak256("ZeroAddress()")));
        manager.recoverSigningKey(address(this), nodeRunner, bytes(""), bytes(""));
    }

    function testRecoverSigningKeyFromNotDaoOrNodeRunner() public {
        uint256 nodeStakeAmount = 4 ether;
        address nodeRunner = accountOne;
        vm.deal(nodeRunner, nodeStakeAmount);
        address eoaRepresentative = accountTwo;
        vm.prank(nodeRunner);
        manager.registerBLSPublicKeys{value: nodeStakeAmount}(
            getBytesArrayFromBytes(blsPubKeyOne),
            getBytesArrayFromBytes(blsPubKeyOne),
            eoaRepresentative
        );
        uint256 amount = 1.5 ether;
        vm.expectRevert(bytes4(keccak256("OnlyDAOOrNodeRunner()")));
        manager.recoverSigningKey(address(this), nodeRunner, blsPubKeyOne, bytes(""));
    }

    function testRecoverSigningKeyFromNotRegisteredBlsKey() public {
        uint256 nodeStakeAmount = 4 ether;
        address nodeRunner = accountOne;
        vm.deal(nodeRunner, nodeStakeAmount);
        address eoaRepresentative = accountTwo;
        vm.prank(nodeRunner);
        manager.registerBLSPublicKeys{value: nodeStakeAmount}(
            getBytesArrayFromBytes(blsPubKeyOne),
            getBytesArrayFromBytes(blsPubKeyOne),
            eoaRepresentative
        );
        uint256 amount = 1.5 ether;
        vm.startPrank(admin);
        vm.expectRevert(bytes4(keccak256("BLSKeyNotRegistered()")));
        manager.recoverSigningKey(address(this), nodeRunner, bytes(""), bytes(""));
        vm.stopPrank();
    }

    function testRageQuitIsReachable() public {
        uint256 nodeStakeAmount = 4 ether;
        address nodeRunner = accountOne;
        vm.deal(nodeRunner, nodeStakeAmount);
        address eoaRepresentative = accountTwo;
        vm.prank(nodeRunner);
        manager.registerBLSPublicKeys{value: nodeStakeAmount}(
            getBytesArrayFromBytes(blsPubKeyOne),
            getBytesArrayFromBytes(blsPubKeyOne),
            eoaRepresentative
        );

        IDataStructures.ETH2DataReport memory _eth2Report;
        IDataStructures.EIP712Signature memory _signatureMetadata;

        vm.startPrank(admin);
        manager.rageQuit(
            nodeRunner,
            abi.encodeWithSelector(
                IBalanceReporter.rageQuitKnot.selector,
                address(0),
                blsPubKeyOne,
                _eth2Report,
                _signatureMetadata
            )
        );
        vm.stopPrank();
    }

    function testMultiPartyRageQuitIsReachable() public {
        uint256 nodeStakeAmount = 4 ether;
        address nodeRunner = accountOne;
        vm.deal(nodeRunner, nodeStakeAmount);
        address eoaRepresentative = accountTwo;
        vm.prank(nodeRunner);
        manager.registerBLSPublicKeys{value: nodeStakeAmount}(
            getBytesArrayFromBytes(blsPubKeyOne),
            getBytesArrayFromBytes(blsPubKeyOne),
            eoaRepresentative
        );

        IDataStructures.ETH2DataReport memory _eth2Report;
        IDataStructures.EIP712Signature[] memory _signatureMetadata;

        vm.startPrank(admin);
        manager.rageQuit(
            nodeRunner,
            abi.encodeWithSelector(
                IBalanceReporter.multipartyRageQuit.selector,
                address(0),
                blsPubKeyOne,
                address(0),
                    address(0),
                _eth2Report,
                _signatureMetadata
            )
        );
        vm.stopPrank();
    }

    function testRecoverSigningKeyWorks() public {
        uint256 nodeStakeAmount = 4 ether;
        address nodeRunner = accountOne;
        vm.deal(nodeRunner, nodeStakeAmount);
        address eoaRepresentative = accountTwo;
        vm.prank(nodeRunner);
        manager.registerBLSPublicKeys{value: nodeStakeAmount}(
            getBytesArrayFromBytes(blsPubKeyOne),
            getBytesArrayFromBytes(blsPubKeyOne),
            eoaRepresentative
        );

        SafeBox safeBox = new SafeBox();
        vm.prank(nodeRunner);
        manager.recoverSigningKey(address(safeBox), nodeRunner, blsPubKeyOne, bytes(""));
    }

    function testTransferOwnershipRevertsWhenNewOwnerIsZero() public {
        vm.prank(admin);
        manager.updateDAOAddress(address(0));

        vm.expectRevert(bytes4(keccak256("ZeroAddress()")));
        manager.transferSmartWalletOwnership(address(0));
    }

    function testTransferOwnershipRevertsWhenKillSwitchNotActivated() public {
        vm.expectRevert(bytes4(keccak256("DAOKillSwitchNotActivated()")));
        manager.transferSmartWalletOwnership(address(this));
    }

    function testTransferOwnershipRevertsWhenNotRegistered() public {
        vm.prank(admin);
        manager.updateDAOAddress(address(0));

        vm.expectRevert(bytes4(keccak256("ZeroAddress()")));
        manager.transferSmartWalletOwnership(address(this));
    }

    function testTransferOwnershipWorks() public {
        vm.prank(admin);
        manager.updateDAOAddress(address(0));

        uint256 nodeStakeAmount = 4 ether;
        address nodeRunner = accountOne;
        vm.deal(nodeRunner, nodeStakeAmount);
        address eoaRepresentative = accountTwo;
        vm.prank(nodeRunner);
        manager.registerBLSPublicKeys{value: nodeStakeAmount}(
            getBytesArrayFromBytes(blsPubKeyOne),
            getBytesArrayFromBytes(blsPubKeyOne),
            eoaRepresentative
        );

        vm.prank(nodeRunner);
        manager.transferSmartWalletOwnership(address(this));
    }

    function testChangeNodeRunnerRevertWhenNewNoderunnerHasSmartWallet()
        public
    {
        address nodeRunner = accountTwo;
        address newNodeRunner = accountThree;
        vm.deal(nodeRunner, 100 ether);
        vm.deal(newNodeRunner, 100 ether);
        registerSingleBLSPubKey(nodeRunner, blsPubKeyOne, accountFour);
        registerSingleBLSPubKey(newNodeRunner, blsPubKeyTwo, accountFour);

        vm.prank(nodeRunner);
        manager.withdrawETHForKnot(nodeRunner, blsPubKeyOne);

        vm.prank(newNodeRunner);
        manager.withdrawETHForKnot(nodeRunner, blsPubKeyTwo);

        vm.expectRevert(bytes4(keccak256("NewRunnerHasASmartWallet()")));
        vm.prank(admin);
        manager.manageNodeRunnerSmartWallet(nodeRunner, newNodeRunner, true);
    }

    function testToggleHouseGatekeeper() public {
        vm.expectRevert(bytes4(keccak256("OnlyDAO()")));
        manager.toggleHouseGatekeeper(true);

        factory = createMockLSDNFactory();
        manager = deployNewLiquidStakingNetwork(factory, admin, true, "LSDN");
        // make 'admin' the 'DAO'
        vm.prank(address(factory));
        manager.updateDAOAddress(admin);

        savETHVault = getSavETHVaultFromManager(manager);
        stakingFundsVault = getStakingFundsVaultFromManager(manager);

        vm.prank(admin);
        manager.updateNodeRunnerWhitelistStatus(
            getAddressArrayFromValues(accountOne),
            true
        );

        vm.deal(accountTwo, 100 ether);
        vm.deal(accountThree, 100 ether);
        depositStakeAndMintDerivativesForDefaultNetwork(
            accountOne,
            accountTwo,
            accountThree,
            blsPubKeyOne
        );

        vm.prank(admin);
        manager.toggleHouseGatekeeper(false);
        vm.prank(admin);
        manager.toggleHouseGatekeeper(true);
    }

    function testUpdateSyndicateActivationDistanceInBlocks() public {
        mockDerivativeMint(blsPubKeyOne);

        vm.expectRevert(bytes4(keccak256("OnlyDAO()")));
        manager.updateSyndicateActivationDistanceInBlocks(100);

        vm.prank(admin);
        manager.updateSyndicateActivationDistanceInBlocks(100);

        assertEq(
            Syndicate(payable(manager.syndicate())).activationDistance(),
            100
        );
    }

    function testConfigureStakeHouse() public {
        vm.expectRevert(bytes4(keccak256("OnlyDAO()")));
        manager.configureStakeHouse(blsPubKeyOne);

        vm.expectRevert(bytes4(keccak256("ZeroAddress()")));
        vm.prank(admin);
        manager.configureStakeHouse(blsPubKeyOne);

        mockDerivativeMint(blsPubKeyOne);

        vm.expectRevert(bytes4(keccak256("HouseAlreadyCreated()")));
        vm.prank(admin);
        manager.configureStakeHouse(blsPubKeyOne);
    }
}
