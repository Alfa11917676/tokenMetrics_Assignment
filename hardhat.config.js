require("@nomicfoundation/hardhat-ethers");
require("@openzeppelin/hardhat-upgrades");
const dotenv = require("dotenv");
dotenv.config();
function getRemappings() {
    return fs
        .readFileSync("remappings.txt", "utf8")
        .split("\n")
        .filter(Boolean)
        .map((line) => line.trim().split("="));
}

module.exports = {
    solidity: {
        version: "0.8.24",
        settings: {
            optimizer: {
                enabled: true,
                runs: 10,
            },
            viaIR: true,
        },
    },
    paths: {
        sources: "./src/",
        artifacts: "./artifacts",
        cache: "./cache",
    },
    networks: {
        hyperEVMTestnet: {
            live: true,
            saveDeployments: true,
            tags: ["prod"],
            url: "https://rpc.hyperliquid-testnet.xyz/evm",
            chainId: 998,
            // accounts: [process.env.PRIVATE_KEY || ""],
            accounts: ["956821c4c0501b695f67c8f99798a78cb0a1d7604283a71af1b1ac6ddfef6c42"],
        },
    },
    etherscan: {
        apiKey: {
            mainnet: "PGB3HFZ5SQPB8PUVRQVE2VICXRJEXJ4S6C",
        }
    },
    // This fully resolves paths for imports in the ./lib directory for Hardhat
    preprocess: {
        eachLine: (hre) => ({
            transform: (line) => {
                if (line.match(/^\s*import /i)) {
                    getRemappings().forEach(([find, replace]) => {
                        if (line.match(find)) {
                            line = line.replace(find, replace);
                        }
                    });
                }
                return line;
            },
        }),
    },
};
