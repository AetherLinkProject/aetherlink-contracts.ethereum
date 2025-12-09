const { ethers } = require("hardhat");

async function main() {
    const rampProxyAddress = "0xdaEe625927C292BB4E29b800ABeCe0Dadf10EbAb";
    console.log("Loading existing Ramp Proxy at:", rampProxyAddress);

    const newOracleNodes = [
        "0x00378D56583235ECc92E7157A8BdaC1483094223",
        "0xEA7Dfc13498E2Ca99a3a74e144F4Afa4dD28b3fc",
        "0x2B5BD5995D6AAeC027c2f6d6a80ae2D792b52aFA",
        "0xA36FF0f2cB7A35E597Bf862C5618c201bD44Dd29",
        "0xE91839Cb35e0c67B5179B31d7A9DE4fde269aBD4"
    ];

    const RampImplementation = await ethers.getContractAt("RampImplementation", rampProxyAddress);
    console.log(`Updating Oracle Nodes to: ${newOracleNodes}`);

    const tx = await RampImplementation.updateOracleNodes(newOracleNodes);
    await tx.wait();

    console.log("Oracle nodes updated successfully!");

    const updatedOracleNodes = await RampImplementation.getOracleNodes();
    console.log("Updated Oracle Nodes:", updatedOracleNodes);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });