const { ethers, network } = require("hardhat")
const dotenv = require("dotenv")
const debug = require("debug")("orbitx-yield:deployment")
const { loadDeployments } = require("./loadDeployment")

dotenv.config()

async function deployment() {
    debug("Deployment started")
    const [admin] = await ethers.getSigners()
    console.log("admin & networkName", admin.address, network.name)

    const { accessController: accessControllerData } = await loadDeployments(
        ["accessController"],
        network.name
    )        
   
    const AccessController = await ethers.getContractFactory("AccessController")
    const accessController = await AccessController.attach(accessControllerData.ContactAddress);
    
    try {
        // for the testnet, we will be using same address for all roles
        const tx = await accessController.initTokenMetricsRoles({   
            admin: admin.address,
            pauser: admin.address,
            manager: admin.address,
            unpauser: admin.address,
            dev: admin.address
        });
        await tx.wait();
        debug("accessController initialized...")
        console.log("AccessController initialized successfully")
    } catch (error) {
        console.error("Failed to initialize AccessController:")
        console.error(`   Error: ${error.message}`)
        if (error.reason) {
            console.error(`   Reason: ${error.reason}`)
        }
        throw error
    }
}

// Only run deployment() if this script is executed directly (not when required)
if (require.main === module) {
    deployment()
        .then(() => process.exit(0))
        .catch((error) => {
            console.error("Deployment failed:", error.message)
            process.exit(1)
        })
}

module.exports = { deployment }
