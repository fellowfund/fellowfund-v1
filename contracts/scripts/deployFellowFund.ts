import { ethers } from "hardhat";
import { Wallet } from "ethers";
import { FellowFund } from "../typechain-types/contracts/FellowFund";
import { fundIfLocalNetwork } from "./utils/network";
import { getPersonalWallet } from "./utils/wallet";

const phalaVerifier = "0xB20F6adf676D488b22962f0C84CD011BE6DD63cB";
const operator = "";

export async function deployFellowFundContract(deployer: Wallet): Promise<FellowFund> {
    console.log("\n#####################################################################");
    console.log("################### FellowFund Contract Deployment ###################");
    console.log("#####################################################################");

    const FellowFundFactory = (await ethers.getContractFactory("FellowFund")).connect(deployer);
    const deployContract = await FellowFundFactory.deploy(phalaVerifier, operator);
    await deployContract.waitForDeployment();
    const fellowFund = await ethers.getContractAt("FellowFund", await deployContract.getAddress(), deployer);

    console.log("\n# Deployment");
    console.log("FellowFund Address: ", await fellowFund.getAddress());
    return fellowFund;
}

async function main() {
    const deployer = getPersonalWallet(ethers.provider);
    await fundIfLocalNetwork([deployer.address]);
    const fellowFund = await deployFellowFundContract(deployer);
    console.log("\n# FellowFund Contract Deployment Completed");
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
