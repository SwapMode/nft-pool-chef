import { ethers } from 'hardhat';
import { BigNumber, Contract } from 'ethers';
import { MAX_UINT256 } from '../test/constants';
import { formatEther } from 'ethers/lib/utils';

export async function deployMasterChef(
  token: string,
  treasury: string,
  weth: string,
  yieldBoooster: string,
  signer
) {
  const factory = await ethers.getContractFactory('MasterChef', signer);
  const instance = await factory.deploy(token, treasury, weth, yieldBoooster);
  await instance.deployed();
  console.log(`MasterChef deployed at: ${instance.address}`);

  return instance;
}
