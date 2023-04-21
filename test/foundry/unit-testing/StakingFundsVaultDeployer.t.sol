pragma solidity ^0.8.13;

import { TestUtils } from "../../utils/TestUtils.sol";
import { StakingFundsVaultDeployer } from "../../../contracts/liquid-staking/StakingFundsVaultDeployer.sol";
import { StakingFundsVault } from "../../../contracts/liquid-staking/StakingFundsVault.sol";
import { UpgradeableBeacon } from "../../../contracts/proxy/UpgradeableBeacon.sol";

contract SavETHVaultDeployerTests is TestUtils {

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
    }

    function testDeployingStakingFundsVault() public {
        StakingFundsVaultDeployer deployer = new StakingFundsVaultDeployer(admin);

        address lpTokenFactory = factory.lpTokenFactory();

        address vault = deployer.deployStakingFundsVault(address(manager), lpTokenFactory);

        assert(vault != address(0));
    }

    function testBeaconUpgradeableFromOnlyOwner() public {
        address upgradeManager = msg.sender;
        UpgradeableBeacon beacon = UpgradeableBeacon(stakingFundsDeployer.beacon());
        address newImplementation = address(new StakingFundsVault());

        vm.startPrank(accountOne);
        vm.expectRevert("Ownable: caller is not the owner");
        beacon.updateImplementation(newImplementation);
        vm.stopPrank();

        vm.startPrank(upgradeManager);
        beacon.updateImplementation(newImplementation);
        vm.stopPrank();
        
        assertEq(beacon.implementation(), newImplementation);
    }

    function testBeaconUpgradeableAfterOwnershipTransfer() public {
        address upgradeManager = msg.sender;
        UpgradeableBeacon beacon = UpgradeableBeacon(stakingFundsDeployer.beacon());
        address newImplementation = address(new StakingFundsVault());

        vm.expectRevert("Ownable: caller is not the owner");
        vm.startPrank(accountOne);
        beacon.transferOwnership(accountOne);
        vm.stopPrank();

        vm.startPrank(upgradeManager);
        beacon.transferOwnership(accountOne);
        vm.stopPrank();

        vm.startPrank(upgradeManager);
        vm.expectRevert("Ownable: caller is not the owner");
        beacon.updateImplementation(newImplementation);
        vm.stopPrank();

        vm.startPrank(accountOne);
        beacon.updateImplementation(newImplementation);
        vm.stopPrank();

        assertEq(beacon.implementation(), newImplementation);
    }
}