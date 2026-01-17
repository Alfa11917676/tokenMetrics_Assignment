// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;
import "forge-std/console.sol";
import "forge-std/Test.sol";
import "@core/utils/AccessController.sol";
import "@core/utils/PauseController.sol";
import "@core/mockUSDC.sol";
import "@core/strategies/MockERC4626Strategy.sol";
import "@core/strategies/MockLockedStrategy.sol";
import "@core/strategies/MockCoreWriter.sol";
import "@core/MultiStrategyVault.sol";
import "@core/RebalanceExecutor.sol";


contract TestSetup is Test {
    
    // Contracts
    AccessController public accessController;
    PauseController public pauseController;
    mockUSDC public usdc;
    MockERC4626Strategy public unlockedStrategy;
    MockLockedStrategy public lockedStrategy;
    MultiStrategyVault public vault;
    MockCoreWriter public coreWriter;
    RebalanceExecutor public rebalanceExecutor;    

    // Variables
    address public admin;
    address public dev;
    address public alice;
    address public bob;
    address public manager;
    address public carol;
    bytes32 public pred = 0x0;
    bytes32 public salt = 0x60d9109846ab510ed75c15f979ae366a8a2ace11d34ba9788c13ac296db50e6e;
    uint256 public delay;
    address[] public proposers;
    address[] public executors;

    // Contract Addresses
    function setUp() public virtual {
        admin = address(uint160(uint(keccak256(abi.encodePacked("admin")))));
        dev = address(uint160(uint(keccak256(abi.encodePacked("dev")))));
        alice = address(uint160(uint(keccak256(abi.encodePacked("alice")))));
        bob = address(uint160(uint(keccak256(abi.encodePacked("bob")))));
        carol = address(uint160(uint(keccak256(abi.encodePacked("carol")))));
        manager = address(uint160(uint(keccak256(abi.encodePacked("manager")))));
        delay = 1 days;
        proposers.push(address(uint160(uint(keccak256(abi.encodePacked("proposer"))))));
        executors.push(address(uint160(uint(keccak256(abi.encodePacked("executor"))))));


        // AccessController
        accessController = new AccessController(uint48(1 days), admin);
        IAccessController.InitRoleSetter memory accessRolesInit = IAccessController.InitRoleSetter({
            admin: admin,
            pauser: dev,
            manager: manager,
            unpauser: dev,
            dev: dev
        });

        // ========================== Testing Access & Pause Controller against multiple scenarios ==========================

        vm.expectRevert(abi.encodeWithSelector(IAccessController.NotDefaultAdmin.selector));
        accessController.initTokenMetricsRoles(accessRolesInit);

        IAccessController.InitRoleSetter memory invalidInitRoles = IAccessController.InitRoleSetter({
            admin: admin,
            pauser: dev,
            manager: manager,
            unpauser: address(0),
            dev: dev
        });

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IAccessController.InvalidInitRoleSetter.selector));
        accessController.initTokenMetricsRoles(invalidInitRoles);

        vm.prank(admin);
        accessController.initTokenMetricsRoles(accessRolesInit);

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IAccessController.RolesAlreadyInitialised.selector));
        accessController.initTokenMetricsRoles(accessRolesInit);

        vm.expectRevert(abi.encodeWithSelector(IPauseController.InputAddressZero.selector));
        pauseController = new PauseController(address(0));

        pauseController = new PauseController(address(accessController));

        usdc = new mockUSDC();
        unlockedStrategy = new MockERC4626Strategy(IERC20(address(usdc)));
        lockedStrategy = new MockLockedStrategy(IERC20(address(usdc)), 1 days);
        coreWriter = new MockCoreWriter();
        vault = new MultiStrategyVault(IERC20(address(usdc)), address(accessController), address(coreWriter), address(pauseController));
        
        // Deploy and set RebalanceExecutor
        rebalanceExecutor = new RebalanceExecutor();
        vm.prank(admin);
        vault.setRebalanceExecutor(address(rebalanceExecutor));

        vm.startPrank(manager);
        vault.addStrategy(address(unlockedStrategy), 6000);
        vault.addStrategy(address(lockedStrategy), 4000);
        vm.stopPrank();
    }
}
