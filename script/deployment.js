const { ethers, upgrades, network } = require("hardhat")
const dotenv = require("dotenv")
const debug = require("debug")("orbitx-yield:deployment")
const fs = require("fs").promises
dotenv.config()

async function deployment() {
    debug("Deployment started")
    const [admin] = await ethers.getSigners()
    console.log("admin & networkName", admin.address, network.name)

    const AccessController = await ethers.getContractFactory("AccessController")
    const PauseController = await ethers.getContractFactory("PauseController")
    const MultiStrategyVault = await ethers.getContractFactory("MultiStrategyVault")
    const MockLockedStrategy = await ethers.getContractFactory("MockLockedStrategy")
    const MockERC4626Strategy = await ethers.getContractFactory("MockERC4626Strategy")
    const MockCoreWriter = await ethers.getContractFactory("MockCoreWriter")
    const mockUSDC = await ethers.getContractFactory("mockUSDC")
    const RebalanceExecutor = await ethers.getContractFactory("RebalanceExecutor")

    // deploy mockUSDC
    const mockUSDCContract = await mockUSDC.deploy()
    await mockUSDCContract.waitForDeployment()
    debug("mockUSDC deployed to:", mockUSDCContract.target)
    await saveContract({
        name: "mockUSDC",
        contractAddress: mockUSDCContract.target,
        dependencies: [],
        deployer: admin.address
    })

    // deploy mockLockedStrategy
    const mockLockedStrategy = await MockLockedStrategy.deploy(mockUSDCContract.target, 1000)
    await mockLockedStrategy.waitForDeployment()
    debug("mockLockedStrategy deployed to:", mockLockedStrategy.target)
    await saveContract({
        name: "mockLockedStrategy",
        contractAddress: mockLockedStrategy.target,
        dependencies: {
            mockUSDC: mockUSDCContract.target,
            lockupDuration: 60 * 60 // 1 hour
        },
        deployer: admin.address
    })

    // deploy mockERC4626Strategy
    const mockERC4626Strategy = await MockERC4626Strategy.deploy(mockUSDCContract.target)
    await mockERC4626Strategy.waitForDeployment()
    debug("mockERC4626Strategy deployed to:", mockERC4626Strategy.target)
    await saveContract({
        name: "mockERC4626Strategy",
        contractAddress: mockERC4626Strategy.target,
            dependencies: {
            mockUSDC: mockUSDCContract.target
        },
        deployer: admin.address
    })


    // deploy coreWriter
    const coreWriter = await MockCoreWriter.deploy()
    await coreWriter.waitForDeployment()
    debug("coreWriter deployed to:", coreWriter.target)
    await saveContract({
        name: "mockCoreWriter",
        contractAddress: coreWriter.target,
        dependencies: [],
        deployer: admin.address,
    })

    // deploy accessController
    const accessController = await AccessController.deploy(
        60 * 60, 
        admin.address
    )
    await accessController.waitForDeployment()
    debug("accessController deployed to:", accessController.target)
    await saveContract({
        name: "accessController",
        contractAddress: accessController.target,
        dependencies: {
            initialDelay: 60 * 60,
            initialDefaultAdmin: admin.address
        },
        deployer: admin.address
    })

    // deploy pauseController
    const pauseController = await PauseController.deploy(
        accessController.target,
    )
    await pauseController.waitForDeployment()
    debug("pauseController deployed to:", pauseController.target)
    await saveContract({
        name: "pauseController",
        contractAddress: pauseController.target,
        dependencies: {
            accessController: accessController.target
        },
        deployer: admin.address
    })

    // deploy rebalanceExecutor
    const rebalanceExecutor = await RebalanceExecutor.deploy()
    await rebalanceExecutor.waitForDeployment()
    debug("rebalanceExecutor deployed to:", rebalanceExecutor.target)
    await saveContract({
        name: "rebalanceExecutor",
        contractAddress: rebalanceExecutor.target,
        dependencies: [],
        deployer: admin.address
    })

    // deploy multiStrategyVault
    const multiStrategyVault = await MultiStrategyVault.deploy(
        mockUSDCContract.target,
        accessController.target,
        coreWriter.target,
        pauseController.target
    )
    await multiStrategyVault.waitForDeployment()
    debug("multiStrategyVault deployed to:", multiStrategyVault.target)
    await saveContract({
        name: "multiStrategyVault",
        contractAddress: multiStrategyVault.target,
        dependencies: {
            mockUSDC: mockUSDCContract.target,
            accessController: accessController.target,
            coreWriter: coreWriter.target,
            pauseController: pauseController.target
        },
        deployer: admin.address
    })
 }
async function saveContract({ name, contractAddress, dependencies, deployer }) {
    const output = {
        name: name,
        ContactAddress: contractAddress,
        dependencies: dependencies,
        deployer: deployer,
        date: new Date()
    }
    let deploymentString = JSON.stringify(output, null, 4)
    const namePath = name ? `${name}/` : ""

    // Define the directory path
    const dir = `deployment/${namePath}`

    // Create the directory if it does not exist, including any necessary parent directories
    await fs.mkdir(dir, { recursive: true })

    // Write the file
    await fs.writeFile(`${dir}${network.name}.${name}.json`, deploymentString)
}

deployment()
