const fs = require("fs").promises
const path = require("path")

async function loadDeployment(contractName, networkName) {
    const deploymentPath = path.join(__dirname, `../deployment/${contractName}/${networkName}.${contractName}.json`)
    try {
        const data = await fs.readFile(deploymentPath, "utf8")
        return JSON.parse(data)
    } catch (error) {
        throw new Error(`Failed to load deployment for ${contractName} on ${networkName}: ${error.message}`)
    }
}

async function loadDeployments(contractNames, networkName) {
    const promises = contractNames.map(name => 
        loadDeployment(name, networkName).then(data => ({ name, data }))
    )
    const results = await Promise.all(promises)
    
    const deploymentData = {}
    results.forEach(({ name, data }) => {
        deploymentData[name] = data
    })
    
    return deploymentData
}

module.exports = { loadDeployment, loadDeployments }

