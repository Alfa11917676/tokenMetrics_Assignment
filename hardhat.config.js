require("@nomicfoundation/hardhat-ethers");
require("@openzeppelin/hardhat-upgrades");
const dotenv = require("dotenv");
const fs = require("fs");
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
        baseTestnet: {
            live: true,
            saveDeployments: true,
            tags: ["staging"],
            url: "https://rpc.ankr.com/base_sepolia/ab79dcfa483af255560a89d3ea080753ab2f1b9707483327db39071c88b01ca6",
            chainId: 84532,
            accounts: [process.env.PRIVATE_KEY || ""],
        },
        base: {
            live: true,
            saveDeployments: true,
            tags: ["staging"],
            url: "https://rpc.ankr.com/base/ab79dcfa483af255560a89d3ea080753ab2f1b9707483327db39071c88b01ca6",
            chainId: 8453,
            accounts: [process.env.PRIVATE_KEY || ""],
        },
        sepolia: {
            live: true,
            saveDeployments: true,
            tags: ["staging"],
            url: "https://eth-sepolia.g.alchemy.com/v2/My_CRCTk9LWEvEyXfPzKLFwLgInbpvwz",
            chainId: 11155111,
            accounts: [process.env.PRIVATE_KEY || ""],
        },
        minato: {
            live: true,
            saveDeployments: true,
            tags: ["staging"],
            url: "https://rpc.minato.soneium.org/",
            chainId: 1946,
            accounts: [process.env.PRIVATE_KEY || ""],
        },
        arbitrum: {
            live: true,
            saveDeployments: true,
            tags: ["staging"],
            url: "https://arb-sepolia.g.alchemy.com/v2/My_CRCTk9LWEvEyXfPzKLFwLgInbpvwz",
            chainId: 421614,
            accounts: [process.env.PRIVATE_KEY || ""],
        },
        soneium: {
            live: true,
            saveDeployments: true,
            tags: ["prod"],
            url: "https://soneium.rpc.scs.startale.com?apikey=1MMV6OevV2VYFcEunLEXOIZEDwkUxdl3",
            chainId: 1868,
            accounts: [process.env.PRIVATE_KEY || ""],
        },
        ethereum: {
            live: true,
            saveDeployments: true,
            tags: ["prod"],
            url: "https://rpc.ankr.com/eth/ab79dcfa483af255560a89d3ea080753ab2f1b9707483327db39071c88b01ca6",
            chainId: 1,
            accounts: [process.env.PRIVATE_KEY || ""],
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
