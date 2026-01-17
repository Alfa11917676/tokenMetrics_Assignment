const { ethers, network } = require("hardhat")
const dotenv = require("dotenv")
const debug = require("debug")("orbitx-yield:deployment")
const { loadDeployments } = require("./loadDeployment")

dotenv.config()

async function setup() {

    const [admin] = await ethers.getSigners()
    console.log("admin & networkName", admin.address, network.name)

    const { multiStrategyVault: multiStrategyVaultData, rebalanceExecutor: rebalanceExecutorData, mockLockedStrategy: mockLockedStrategyData, mockERC4626Strategy: mockERC4626StrategyData } = await loadDeployments(
        ["multiStrategyVault", "rebalanceExecutor", "mockLockedStrategy", "mockERC4626Strategy"],
        network.name
    )
    
    const MultiStrategyVault = await ethers.getContractFactory("MultiStrategyVault")
    const multiStrategyVault = await MultiStrategyVault.attach(multiStrategyVaultData.ContactAddress)

    // set up rebalancer
    let tx = await multiStrategyVault.setRebalanceExecutor(rebalanceExecutorData.ContactAddress)
    await tx.wait()
    debug("rebalancer set successfully")

    // add the strategies to the vault
    tx = await multiStrategyVault.addStrategy(mockLockedStrategyData.ContactAddress, 4000)
    await tx.wait()
    debug("strategy added successfully")
    tx = await multiStrategyVault.addStrategy(mockERC4626StrategyData.ContactAddress, 6000)
    await tx.wait()
    debug("strategy added successfully")

    // set the allocations
    tx = await multiStrategyVault.setAllocations([4000, 6000])
    await tx.wait()
    debug("allocations set successfully")
}

if (require.main === module) {
    setup().catch((error) => {
        console.error("Error:", error);
        process.exitCode = 1;
    });
}
