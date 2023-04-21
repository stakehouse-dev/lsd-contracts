pragma solidity ^0.8.13;

// SPDX-License-Identifier: MIT

import "forge-std/console.sol";

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { IERC20 } from "@blockswaplab/stakehouse-solidity-api/contracts/IERC20.sol";
import { SavETHVaultDeployer } from "../../../contracts/liquid-staking/SavETHVaultDeployer.sol";
import { StakingFundsVaultDeployer } from "../../../contracts/liquid-staking/StakingFundsVaultDeployer.sol";
import { LiquidStakingManager } from "../../../contracts/liquid-staking/LiquidStakingManager.sol";
import { LPTokenFactory } from "../../../contracts/liquid-staking/LPTokenFactory.sol";
import { LPToken } from "../../../contracts/liquid-staking/LPToken.sol";
import { LSDNFactory } from "../../../contracts/liquid-staking/LSDNFactory.sol";
import { MockLSDNFactory } from "../../../contracts/testing/liquid-staking/MockLSDNFactory.sol";
import { SyndicateFactory } from "../../../contracts/syndicate/SyndicateFactory.sol";
import { SyndicateMock } from "../../../contracts/testing/syndicate/SyndicateMock.sol";
import { OwnableSmartWalletFactory } from "../../../contracts/smart-wallet/OwnableSmartWalletFactory.sol";
import { MockERC20 } from "../../../contracts/testing/MockERC20.sol";
import { MockLiquidStakingManager } from "../../../contracts/testing/liquid-staking/MockLiquidStakingManager.sol";
import { MockAccountManager } from "../../../contracts/testing/stakehouse/MockAccountManager.sol";
import { MockSlotRegistry } from "../../../contracts/testing/stakehouse/MockSlotRegistry.sol";
import { MockStakeHouseUniverse } from "../../../contracts/testing/stakehouse/MockStakeHouseUniverse.sol";
import { MockBrandNFT } from "../../../contracts/testing/stakehouse/MockBrandNFT.sol";
import { StakeHouseRegistry } from "../../../contracts/testing/stakehouse/StakeHouseRegistry.sol";
import { MockSavETHVault } from "../../../contracts/testing/liquid-staking/MockSavETHVault.sol";
import { IDataStructures } from "@blockswaplab/stakehouse-contract-interfaces/contracts/interfaces/IDataStructures.sol";
import { OptionalGatekeeperFactory } from "../../../contracts/liquid-staking/OptionalGatekeeperFactory.sol";
import { UpgradeableBeacon } from "../../../contracts/proxy/UpgradeableBeacon.sol";
import { MockImplementationUpgrade } from "../../../contracts/testing/liquid-staking/MockImplementationUpgrade.sol";
import { TestUtils } from "../../utils/TestUtils.sol";

contract LSDNFactoryTest is TestUtils {

    MockERC20 public sETH = new MockERC20("sETH", "sETH", admin);

    function setUp() public {
        vm.startPrank(accountFive); // this will mean it gets dETH initial supply
        factory = createMockLSDNFactory();
        vm.stopPrank();

        // Deploy 1 network
        manager = deployNewLiquidStakingNetwork(
            factory,
            admin,
            false,
            "LSDN"
        );

        savETHVault = MockSavETHVault(address(manager.savETHVault()));
        assertEq(savETHVault.dETHToken().balanceOf(accountFive), 125_000 ether);
    }

    function testDeployNewLiquidStakingDerivativeNetworkIsSuccessfulWithValidParams() public {
        assertEq(manager.numberOfKnots(), 0);
        assertEq(manager.enableWhitelisting(), false);
        assertEq(manager.stakehouse(), address(0));
        assertEq(manager.syndicate(), address(0));
        assertEq(manager.dao(), address(factory));
        assertTrue(address(manager.gatekeeper()) == address(0));
        assertEq(manager.stakehouseTicker(), "LSDN");
        assertTrue(address(manager.stakingFundsVault()) != address(0));
        assertTrue(address(manager.savETHVault()) != address(0));

        vm.prank(address(factory));
        manager.updateDAOAddress(admin);

        vm.prank(admin);
        manager.updateWhitelisting(true);
        assertEq(manager.enableWhitelisting(), true);
    }

    function testStakeKnotAndMintDerivatives() public {
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

        address nodeRunnerSmartWallet = manager.smartWalletOfNodeRunner(nodeRunner);
        assertTrue(nodeRunnerSmartWallet != address(0));
        assertEq(nodeRunnerSmartWallet.balance, nodeStakeAmount);

        MockAccountManager(manager.accountMan()).setLifecycleStatus(blsPubKeyOne, 1);
        manager.setIsPartOfNetwork(blsPubKeyOne, true);

        address lp = accountThree;
        uint256 lpStakeAmount = 24 ether;
        savETHVault.depositETHForStaking{value: lpStakeAmount}(blsPubKeyOne, lpStakeAmount);

        vm.deal(address(admin), nodeStakeAmount);
        vm.startPrank(admin);
        manager.stakingFundsVault().depositETHForStaking{value: nodeStakeAmount}(blsPubKeyOne, nodeStakeAmount);
        vm.stopPrank();

        assertEq(manager.smartWalletRepresentative(nodeRunnerSmartWallet), eoaRepresentative);

        address predictedSyndicateAddress = manager.getNetworkFeeRecipient();
        assertTrue(predictedSyndicateAddress != address(0));
        assertEq(manager.syndicate(), address(0));

        stakeSingleBlsPubKey(blsPubKeyOne);

        assertEq(manager.smartWalletRepresentative(nodeRunnerSmartWallet), address(0));
        assertEq(manager.smartWalletDormantRepresentative(nodeRunnerSmartWallet), eoaRepresentative);

        // TX router expected to have the 32 ETH as the mock router is not connected to Ethereum deposit contract
        assertEq(address(manager.txRouter()).balance, 32 ether);
        assertEq(manager.stakedKnotsOfSmartWallet(manager.smartWalletOfKnot(blsPubKeyOne)), 1);
        assertEq(address(manager.stakingFundsVault()).balance, 0);
        assertEq(nodeRunnerSmartWallet.balance, 0);

        MockAccountManager(manager.accountMan()).setLifecycleStatus(blsPubKeyOne, 2);

        mintDerivativesSingleBlsPubKey(blsPubKeyOne);

        assertEq(predictedSyndicateAddress, manager.syndicate());
    }

    function testRegisterKeysAndWithdrawETHAsNodeRunner() public {
        address house = address(new StakeHouseRegistry());

        uint256 nodeStakeAmount = 4 ether;
        address nodeRunner = accountOne;
        vm.deal(nodeRunner, nodeStakeAmount);

        address eoaRepresentative = accountTwo;

        MockAccountManager(manager.accountMan()).setLifecycleStatus(blsPubKeyOne, 0);

        vm.prank(nodeRunner);
        manager.registerBLSPublicKeys{value: nodeStakeAmount}(
            getBytesArrayFromBytes(blsPubKeyOne),
            getBytesArrayFromBytes(blsPubKeyOne),
            eoaRepresentative
        );

        MockAccountManager(manager.accountMan()).setLifecycleStatus(blsPubKeyOne, 1);
        manager.setIsPartOfNetwork(blsPubKeyOne, true);

        address nodeRunnerSmartWallet = manager.smartWalletOfNodeRunner(nodeRunner);
        assertEq(nodeRunnerSmartWallet.balance, 4 ether);

        vm.prank(nodeRunner);
        manager.withdrawETHForKnot(nodeRunner, blsPubKeyOne);
    }

    function testCreateFirstKnotAndReceiveSyndicateRewards() public {
        // Set up users and ETH
        address nodeRunner = accountOne; vm.deal(nodeRunner, 4 ether);
        address feesAndMevUser = accountTwo; vm.deal(feesAndMevUser, 4 ether);
        address savETHUser = accountThree; vm.deal(savETHUser, 24 ether);

        // Register a BLS public key
        registerSingleBLSPubKey(nodeRunner, blsPubKeyFour, accountFour);
        
        // Stake in staking funds savETHVault and savETH savETHVault
        vm.startPrank(savETHUser);
        savETHVault.depositETHForStaking{value: 24 ether}(blsPubKeyFour, 24 ether);
        vm.stopPrank();
        assertEq(manager.savETHVault().lpTokenForKnot(blsPubKeyFour).balanceOf(savETHUser), 24 ether);

        vm.startPrank(feesAndMevUser);
        manager.stakingFundsVault().depositETHForStaking{value: 4 ether}(blsPubKeyFour, 4 ether);
        vm.stopPrank();
        assertEq(manager.stakingFundsVault().lpTokenForKnot(blsPubKeyFour).balanceOf(feesAndMevUser), 4 ether);

        // Send pooled 32 ETH to Ethereum deposit contract and fast forward minting derivatives
        stakeAndMintDerivativesSingleKey(blsPubKeyFour);

        // move block forward to activate rewards
        vm.roll(block.number + 1 + (5*32));

        // Send syndicate some EIP1559 rewards
        uint256 eip1559Tips = 0.6743 ether;
        sendEIP1559RewardsToSyndicateAtAddress(eip1559Tips, manager.syndicate());

        // As a fees and MEV user, lets preview how much ETH has been accrued before claiming
        LPToken[] memory tokens = new LPToken[](1);
        tokens[0] = manager.stakingFundsVault().lpTokenForKnot(blsPubKeyFour);
        assertEq(
            manager.stakingFundsVault().batchPreviewAccumulatedETH(feesAndMevUser, tokens),
            (eip1559Tips / 2) - 1
        );

        // Syndicate registers that the EIP1559 tips have been received
        SyndicateMock syndicate = SyndicateMock(payable(manager.syndicate()));
        assertEq(
            syndicate.totalETHReceived(),
            eip1559Tips
        );

        vm.warp(block.timestamp + 3 hours);

        // Check that the balance of the feesAndMevUser increases by the expected amount i.e. 50% of rewards
        assertEq(feesAndMevUser.balance, 0);
        vm.startPrank(feesAndMevUser);
        manager.stakingFundsVault().claimRewards(feesAndMevUser, getBytesArrayFromBytes(blsPubKeyFour));
        vm.stopPrank();
        assertEq(feesAndMevUser.balance, (0.33715 ether) - 1);

        assertEq(
            syndicate.totalETHReceived(),
            eip1559Tips
        );

        assertEq(
            syndicate.accumulatedETHPerCollateralizedSlotPerKnot(),
            eip1559Tips / 2
        );

        assertEq(
            syndicate.lastSeenETHPerCollateralizedSlotPerKnot(),
            eip1559Tips / 2
        );

        assertEq(
            syndicate.totalETHProcessedPerCollateralizedKnot(blsPubKeyFour),
            0
        );

        assertEq(
            syndicate.accruedEarningPerCollateralizedSlotOwnerOfKnot(blsPubKeyFour, manager.smartWalletOfNodeRunner(nodeRunner)),
            0
        );

        // Allow node runner to claim their share of network revenue
        assertEq(nodeRunner.balance, 0);
        assertEq(
            syndicate.previewUnclaimedETHAsCollateralizedSlotOwner(manager.smartWalletOfNodeRunner(nodeRunner), blsPubKeyFour),
            (0.33715 ether)
        );

        vm.startPrank(nodeRunner);
        manager.claimRewardsAsNodeRunner(nodeRunner, getBytesArrayFromBytes(blsPubKeyFour));
        vm.stopPrank();
        assertEq(nodeRunner.balance, 0.33715 ether);

        // Syndicate is left with 1 wei due to rounding issues processing free floating (thanks solidity)
        assertEq(manager.syndicate().balance, 1);

        // Ensure that node runner cannot claim any more rewards
        vm.expectRevert(bytes4(keccak256("NothingReceived()")));
        vm.prank(nodeRunner);
        manager.claimRewardsAsNodeRunner(nodeRunner, getBytesArrayFromBytes(blsPubKeyFour));
    }

    function testThatAfterFirstKnotSecondKnotOnwardsJoinsTheLSDHouse() public {
        // Set up users and ETH
        address nodeRunner = accountOne; vm.deal(nodeRunner, 12 ether);
        address feesAndMevUserOne = accountTwo; vm.deal(feesAndMevUserOne, 4 ether);
        address feesAndMevUserTwo = accountFive; vm.deal(feesAndMevUserTwo, 4 ether);
        address savETHUser = accountThree; vm.deal(savETHUser, 24 ether * 3);

        // Register three BLS public keys
        registerSingleBLSPubKey(nodeRunner, blsPubKeyOne, accountFour);
        registerSingleBLSPubKey(nodeRunner, blsPubKeyTwo, accountFour);
        registerSingleBLSPubKey(nodeRunner, blsPubKeyThree, accountFour);

        // Deposit into the savETH pool for each KNOT
        vm.startPrank(savETHUser);
        savETHVault.depositETHForStaking{value: 24 ether}(blsPubKeyOne, 24 ether);
        savETHVault.depositETHForStaking{value: 24 ether}(blsPubKeyTwo, 24 ether);
        savETHVault.depositETHForStaking{value: 24 ether}(blsPubKeyThree, 24 ether);
        vm.stopPrank();

        // Deposit into the staking funds vaults
        vm.startPrank(feesAndMevUserOne);
        manager.stakingFundsVault().depositETHForStaking{value: 4 ether}(blsPubKeyOne, 4 ether);
        vm.stopPrank();

        vm.startPrank(feesAndMevUserTwo);
        manager.stakingFundsVault().depositETHForStaking{value: 4 ether}(blsPubKeyTwo, 4 ether);
        vm.stopPrank();

        // Create the house
        stakeAndMintDerivativesSingleKey(blsPubKeyOne);

        // 2nd knot - joins house and mint derivatives
        stakeAndMintDerivativesSingleKey(blsPubKeyTwo);

        // Push forward to allow 2 kntos to activate
        vm.roll(block.number + 1 + (50*32));

        // Send syndicate some EIP1559 rewards
        uint256 eip1559Tips = 0.9244 ether;
        sendEIP1559RewardsToSyndicateAtAddress(eip1559Tips, manager.syndicate());

        // Syndicate registers that the EIP1559 tips have been received
        SyndicateMock syndicate = SyndicateMock(payable(manager.syndicate()));
        assertEq(
            syndicate.totalETHReceived(),
            eip1559Tips
        );

        vm.warp(block.timestamp + 3 hours);

        // claim 25% of rewards from staking funds vault
        assertEq(feesAndMevUserOne.balance, 0);
        assertEq(manager.stakingFundsVault().totalShares(), 8 ether);
        assertEq(manager.stakingFundsVault().totalRewardsReceived(), 0);

        address stakingFundsVault = address(manager.stakingFundsVault());
        assertEq(stakingFundsVault.balance, 0);

        uint256 ETHDueToStakingFundsVaultForBLSOne = syndicate.previewUnclaimedETHAsFreeFloatingStaker(stakingFundsVault, blsPubKeyOne);
        uint256 ETHDueToStakingFundsVaultForBLSTwo = syndicate.previewUnclaimedETHAsFreeFloatingStaker(stakingFundsVault, blsPubKeyTwo);

        // 1 wei precision loss per user hence minus 2
        assertEq(ETHDueToStakingFundsVaultForBLSOne + ETHDueToStakingFundsVaultForBLSTwo, (eip1559Tips / 2) - 2);

        // let fees and mev user one claim and get 25% of rewards
        vm.startPrank(feesAndMevUserOne);
        manager.stakingFundsVault().claimRewards(feesAndMevUserOne, getBytesArrayFromBytes(blsPubKeyOne, blsPubKeyTwo));
        vm.stopPrank();
        assertEq(feesAndMevUserOne.balance, (eip1559Tips / 4) - 1);

        vm.startPrank(feesAndMevUserTwo);
        manager.stakingFundsVault().claimRewards(feesAndMevUserTwo, getBytesArrayFromBytes(blsPubKeyTwo));
        vm.stopPrank();
        assertEq(feesAndMevUserTwo.balance, (eip1559Tips / 4) - 1);

        vm.startPrank(nodeRunner);
        manager.claimRewardsAsNodeRunner(nodeRunner, getBytesArrayFromBytes(blsPubKeyOne, blsPubKeyTwo));
        vm.stopPrank();
        assertEq(nodeRunner.balance, eip1559Tips / 2);

        // withdraw dETH from the protected vaults
        IERC20 dETHToken = savETHVault.dETHToken();
        vm.startPrank(accountFive);
        dETHToken.transfer(address(savETHVault.saveETHRegistry()), 24 ether * 2);
        vm.stopPrank();

        vm.expectRevert("Empty arrays");
        savETHVault.burnLPTokensByBLS(getEmptyBytesArray(), getUint256ArrayFromValues(24 ether, 24 ether));
        vm.expectRevert("Inconsistent array length");
        savETHVault.burnLPTokensByBLS(getBytesArrayFromBytes(blsPubKeyOne, blsPubKeyTwo), getEmptyUint256Array());

        vm.startPrank(savETHUser);
        savETHVault.burnLPTokensByBLS(getBytesArrayFromBytes(blsPubKeyOne, blsPubKeyTwo), getUint256ArrayFromValues(24 ether, 24 ether));
        vm.stopPrank();
        assertEq(dETHToken.balanceOf(savETHUser), 48 ether);
    }

    function testBeaconUpgradeableFromOnlyOwner() public {
        address upgradeManager = accountFive;
        UpgradeableBeacon liquidStakingManagerBeacon = UpgradeableBeacon(factory.liquidStakingManagerBeacon());
        address newImplementation = address(new MockImplementationUpgrade());

        vm.expectRevert("Ownable: caller is not the owner");
        liquidStakingManagerBeacon.updateImplementation(newImplementation);

        vm.startPrank(upgradeManager);
        liquidStakingManagerBeacon.updateImplementation(newImplementation);
        vm.stopPrank();

        assertEq(MockImplementationUpgrade(address(manager)).isNewImplementation(), true);
    }

    function testBeaconUpgradeableAfterOwnershipTransfer() public {
        address upgradeManager = accountFive;
        UpgradeableBeacon liquidStakingManagerBeacon = UpgradeableBeacon(factory.liquidStakingManagerBeacon());
        address newImplementation = address(new MockImplementationUpgrade());

        vm.expectRevert("Ownable: caller is not the owner");
        liquidStakingManagerBeacon.transferOwnership(accountOne);

        vm.startPrank(upgradeManager);
        liquidStakingManagerBeacon.transferOwnership(accountOne);
        vm.stopPrank();

        vm.startPrank(upgradeManager);
        vm.expectRevert("Ownable: caller is not the owner");
        liquidStakingManagerBeacon.updateImplementation(newImplementation);
        vm.stopPrank();

        vm.startPrank(accountOne);
        liquidStakingManagerBeacon.updateImplementation(newImplementation);
        vm.stopPrank();

        assertEq(MockImplementationUpgrade(address(manager)).isNewImplementation(), true);
    }

    function testUUPSUpgradeable() public {
        bytes32 implementationSlot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        address implementation = address(new LSDNFactory());
        LSDNFactory lsdnFactory = LSDNFactory(address(new ERC1967Proxy(
                address(implementation),
                abi.encodeCall(
                    LSDNFactory.init,
                    (
                        LSDNFactory.InitParams(
                            address(managerImplementation),
                            address(managerImplementation), // MockLSDNFactory will override the _syndicateFactory param
                            address(lpTokenFactory),
                            address(smartWalletFactory),
                            address(brand),
                            address(vaultDeployer),
                            address(stakingFundsDeployer),
                            address(keeperDeployer),
                            address(gSavETHVaultImplementation),
                            address(gMevImplementation),
                            address(giantLPDeployer),
                            accountFive
                        )
                    )
                )
            )));
        address upgradeManager = accountFive;

        // upgrade to new implementation address
        vm.startPrank(upgradeManager);
        address newImplementation = address(new LSDNFactory());
        lsdnFactory.upgradeTo(address(newImplementation));
        vm.stopPrank();
        assertEq(address(uint160(uint256(vm.load(address(lsdnFactory), implementationSlot)))), address(newImplementation));

        // test upgrade after renounce ownership
        vm.startPrank(upgradeManager);
        lsdnFactory.renounceOwnership();
        vm.stopPrank();
        assertEq(lsdnFactory.owner(), address(0));

        vm.startPrank(upgradeManager);
        vm.expectRevert("Ownable: caller is not the owner");
        lsdnFactory.upgradeTo(address(newImplementation));
        vm.stopPrank();
    }
}