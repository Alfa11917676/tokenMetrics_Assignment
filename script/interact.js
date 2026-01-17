// script to interact with the vault

const { ethers, network } = require("hardhat")
const dotenv = require("dotenv")
const debug = require("debug")("orbitx-yield:interact")
const { loadDeployments } = require("./loadDeployment")

dotenv.config()

async function interact() {
 
    const [admin] = await ethers.getSigners()
    console.log("admin & networkName", admin.address, network.name)

    const { multiStrategyVault: multiStrategyVaultData, mockUSDC: mockUSDCData } = await loadDeployments(
        ["multiStrategyVault", "mockUSDC"],
        network.name
    )
    debug("multiStrategyVaultData", multiStrategyVaultData)
    debug("mockUSDCData", mockUSDCData)
    console.log("multiStrategyVaultData", multiStrategyVaultData)

    const MultiStrategyVault = await ethers.getContractFactory("MultiStrategyVault")
    const multiStrategyVault = await MultiStrategyVault.attach(multiStrategyVaultData.ContactAddress)

    const MockUSDC = await ethers.getContractFactory("mockUSDC")
    const mockUSDC = await MockUSDC.attach(mockUSDCData.ContactAddress)

    // mint the assets
    let tx = await mockUSDC.mint(admin.address, ethers.parseUnits("10000", 6))
    await tx.wait()
    debug("assets minted successfully")

    // approve the vault to spend the assets
    tx = await mockUSDC.approve(multiStrategyVaultData.ContactAddress, ethers.parseUnits("10000", 6))
    await tx.wait()
    debug("assets approved successfully")

    // deposit the assets
    tx = await multiStrategyVault.deposit(ethers.parseUnits("10000", 6), admin.address)
    await tx.wait()
    debug("assets deposited successfully")

    // rebalance the vault
    tx = await multiStrategyVault.rebalance()
    await tx.wait()
    debug("rebalanced successfully")
}

if (require.main === module) {
    interact().catch((error) => {
        console.error("Error:", error);
        process.exitCode = 1;
    });
}