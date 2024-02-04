import * as dotenv from 'dotenv';
import { HardhatUserConfig } from 'hardhat/config';
import '@nomicfoundation/hardhat-toolbox';

dotenv.config();

const accounts = process.env.DEV_KEY !== undefined ? [process.env.DEV_KEY] : [];

const config: HardhatUserConfig = {
  solidity: {
    compilers: [
      {
        version: '0.8.15',
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
    ],
  },
  networks: {
    hardhat: {
      forking: {
        url: process.env.ARBITRUM_RPC || '',
        blockNumber: 97443294,
      },
    },
    arbitrum: {
      url: process.env.ARBITRUM_RPC || '',
      accounts,
    },
    optimism: {
      url: `${process.env.OPTIMISM_RPC}`,
      accounts,
    },
    base: {
      url: `${process.env.BASE_RPC}`,
      accounts,
      chainId: 8453,
      gas: 500000,
      gasPrice: 100,
    },
    baseGoerli: {
      url: process.env.BASE_GOERLI_RPC,
      accounts,
      chainId: 84531,
      // gas: 500000,
      // gasPrice: 100,
    },
  },
  etherscan: {
    apiKey: process.env.ETHERSCAN_API_KEY,
  },
};

export default config;
