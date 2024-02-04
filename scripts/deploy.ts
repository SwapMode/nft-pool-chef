import { ethers } from 'hardhat';
import { parseUnits } from 'ethers/lib/utils';

const CHEF_MAINNET = '';
const CHEF_TESTNET = '';
const FACTORY = '';
const TREASURY = '0x03d4C4b1B115c068Ef864De2e21E724a758892A2'; // Dev acount
const YIELD_BOOSTER_MAINNET = '0x0fE9E7B39dbdfe32c9F37FAcCec6b33d290CbF50';
const YIELD_BOOSTER_TESTNET = '0x4Ab974442D6e67c32E40f44BcDC22388F3F16d9e';
const PROTOCOL_TOKEN_MAINNET = '0xFDa619b6d20975be80A10332cD39b9a4b0FAa8BB';
const PROTOCOL_TOKEN_TESTNET = '0xB687282AD4Fb8897D5Cd41f3C1A54DeB4cc88625';
const XTOKEN_MAINNET = '0xFb68BBfaEF679C1E653b5cE271a0A383c0df6B45';
const XTOKEN_TESTNET = '0x2ee99Be3c520B7Bd64f51641c3e7Ef28950E03B7';

async function main() {
  try {
    // Contracts are deployed from 0.7.6 repo
    const WETH = '0x4200000000000000000000000000000000000006'; // BASE chain WETH
    const WETH_PER_SECOND = parseUnits('0.0000006');

    // if (block.timestamp < _startTime && _startTime >= _mainToken.lastEmissionTime()) {
    //   revert InvalidStartTime();
    // }
    const START_TIME = 0;

    // Chef can't start until token emissions something
    const chef = await ethers.getContractFactory('MasterChef');
    const instance = await chef.deploy(
      PROTOCOL_TOKEN_MAINNET,
      TREASURY,
      WETH,
      WETH_PER_SECOND,
      START_TIME,
      YIELD_BOOSTER_TESTNET
    );

    await instance.deployed();
    console.log(`MasterChef deployed to: ${instance.address}`);
  } catch (error) {
    console.error(error);
    process.exitCode = 1;
  }
}

main();
