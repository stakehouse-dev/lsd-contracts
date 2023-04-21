pragma solidity ^0.8.13;

import { TestUtils } from "../../utils/TestUtils.sol";
import { SavETHVaultDeployer } from "../../../contracts/liquid-staking/SavETHVaultDeployer.sol";
import { SavETHVault } from "../../../contracts/liquid-staking/SavETHVault.sol";
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

    function testDeployingSavETHVaultOnWrongNetwork() public {
        SavETHVaultDeployer deployer = new SavETHVaultDeployer(admin);

        address lpTokenFactory = factory.lpTokenFactory();
        vm.expectRevert("Network unsupported");
        address vault = deployer.deploySavETHVault(address(manager), lpTokenFactory);

        assert(vault == address(0));
    }

    function testBeaconUpgradeableFromOnlyOwner() public {
        address upgradeManager = msg.sender;
        UpgradeableBeacon beacon = UpgradeableBeacon(vaultDeployer.beacon());
        address newImplementation = address(new SavETHVault());

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
        UpgradeableBeacon beacon = UpgradeableBeacon(vaultDeployer.beacon());
        address newImplementation = address(new SavETHVault());

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