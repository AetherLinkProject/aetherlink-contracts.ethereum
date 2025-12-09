const { run } = require("hardhat");

async function main() {
    // const contractAddress = "0xdaEe625927C292BB4E29b800ABeCe0Dadf10EbAb"
    const contractAddress = "0xebC99751DF4b3807849263964aD38d6f6c5e3531"; // sepolia
    // const contractAddress = "0x986ff249946fCd04b116d95166c8D4a4c9142CaC"; // bsc test

    // const newOracleNodes = [
    //     "0x00378D56583235ECc92E7157A8BdaC1483094223",
    //     "0xEA7Dfc13498E2Ca99a3a74e144F4Afa4dD28b3fc",
    //     "0x2B5BD5995D6AAeC027c2f6d6a80ae2D792b52aFA",
    //     "0xA36FF0f2cB7A35E597Bf862C5618c201bD44Dd29",
    //     "0xE91839Cb35e0c67B5179B31d7A9DE4fde269aBD4"
    // ];
    // const implementationAddress = "0x986ff249946fCd04b116d95166c8D4a4c9142CaC";
    // const constructorArgs = [newOracleNodes, implementationAddress];
    const constructorArgs = [];

    // const contractName = "contracts/Ramp.sol:Ramp";
    const contractName = "contracts/RampImplementation.sol:RampImplementation";

    console.log(`Verifying contract at address: ${contractAddress}...`);

    try {
        await run("verify:verify", {
            address: contractAddress,
            constructorArguments: constructorArgs,
            contract: contractName,
        });
        console.log(`RampImplementation contract verified at address: ${contractAddress}`);
    } catch (error) {
        if (error.message.toLowerCase().includes("already verified")) {
            console.log("Contract is already verified.");
        } else {
            console.error("Verification failed:", error);
        }
    }
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });