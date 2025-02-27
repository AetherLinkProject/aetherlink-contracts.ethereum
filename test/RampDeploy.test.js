const { expect } = require("chai");

describe("Ramp Proxy Deployment", function () {
    it("should correctly deploy logic and Proxy contracts, and initialize RampImplementation", async function () {
        const [owner, addr1, addr2] = await ethers.getSigners();
        wallet1 = new ethers.Wallet("59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d");
        wallet2 = new ethers.Wallet("5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a");
        wallet3 = new ethers.Wallet("7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6");
        const initialOracleNodes = [wallet1.address, wallet2.address, wallet3.address];

        // Deploy Ramp Contract
        const Ramp = await ethers.getContractFactory("Ramp");
        const RampImplementation = await ethers.getContractFactory("RampImplementation");
        const rampImplementation = await RampImplementation.deploy();
        const rampProxy = await Ramp.deploy(initialOracleNodes, rampImplementation.address);
        const ramp = RampImplementation.attach(rampProxy.address);

        const currentNodes = await ramp.getOracleNodes();
        expect(currentNodes[0]).to.equal(initialOracleNodes[0]);
        expect(currentNodes[1]).to.equal(initialOracleNodes[1]);
        expect(currentNodes[2]).to.equal(initialOracleNodes[2]);
    });
});