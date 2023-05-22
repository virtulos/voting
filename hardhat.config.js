require('dotenv').config({path: __dirname + '/.env'})
require("@nomiclabs/hardhat-etherscan");
require("@nomiclabs/hardhat-ethers");

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
    defaultNetwork: "hardhat",
    solidity: {
        compilers: [
            {version: "0.8.18", settings: {optimizer: {enabled: true, runs: 200}}}
        ]
    },
    networks: {
        hardhat: {
            chainId: 1,
            gasPrice: 'auto',
            throwOnTransactionFailures: true,
            throwOnCallFailures: true,
            allowUnlimitedContractSize: true,
            loggingEnabled: false,
            accounts: {mnemonic: 'test test test test test test test test test test test junk'}
        },
        BSCTestnet: {
            url: process.env.BSC_TESTNET_RPC || 'https://bsc-dataseed.binance.org/',
            accounts: (
                process.env.BSC_TESTNET_PRIVATE_KEY
            ).split(','),
            timeout: 300000,
            gas: 15000000
        }
    }
};
