const { expect } = require("chai");
const { ethers } = require("hardhat");
const { loadFixture } = require("@nomicfoundation/hardhat-network-helpers");
const { anyValue } = require("@nomicfoundation/hardhat-chai-matchers/withArgs");

describe("Ramp", function () {
    const TOKEN_AMOUNT = ethers.utils.parseEther("100");

    async function deployRampFixture() {
        // For Wallet
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

        // For Mock Contract
        const RouterMock = await ethers.getContractFactory("MockRouter");
        mockRouter = await RouterMock.deploy();
        await mockRouter.deployed();

        return { ramp, rampProxy, mockRouter, owner, addr1, addr2, wallet1, wallet2, wallet3 }
    }


    describe("Deploy", function () {
        describe("owner test", function () {
            it("Should be contract deployer", async function () {
                const { ramp, owner } = await loadFixture(deployRampFixture);
                expect(await ramp.owner()).to.equal(owner.address);
            });
        })

        describe("update contract test", function () {
            it("Should revert when address is not a contract", async function () {
                const { owner, rampProxy } = await loadFixture(deployRampFixture);
                error = 'DESTINATION_ADDRESS_IS_NOT_A_CONTRACT'
                await expect(rampProxy.updateImplementation(owner.address))
                    .to.be.revertedWith(error);
            });
        })

        describe("update contract config test", function () {
            it("should initialize oracle nodes correctly", async () => {
                const { ramp, addr1, addr2 } = await loadFixture(deployRampFixture);
                const oracleNodes = await ramp.getOracleNodes();
                expect(oracleNodes.length).to.equal(3);
                expect(oracleNodes).to.include(addr1.address);
                expect(oracleNodes).to.include(addr2.address);
            });

            it("should calculate the correct signature threshold", async () => {
                const { ramp } = await loadFixture(deployRampFixture);
                const expectedThreshold = Math.floor((3 + 1) / 2) + 1; // Threshold = 2 when 3 nodes exist
                expect(await ramp.signatureThreshold()).to.equal(expectedThreshold);
            });
        })
    });

    describe("SendRequest", () => {
        it("should emit RequestSent event and compute correct messageId on valid inputs", async () => {
            const { ramp, owner, addr1, mockRouter } = await loadFixture(deployRampFixture);
            const sourceChainId = 31337;
            const targetChainId = 2;
            const receiver = "0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0";
            const message = "Hello Receiver";
            const tokenAmount = getValidTokenAmount();
            // const block = await ethers.provider.getBlock("latest");
            // const currentTimestamp = block.timestamp;
            // const expectedMessageId = generateMessageId(addr1.address, targetChainId, receiver, message, tokenAmount, currentTimestamp);
            // const tokenAmountBytes = encodeTokenAmount(tokenAmount);
            // const tokenTransferMetadataBytes = ethers.utils.defaultAbiCoder.decode(
            //     ["address", "uint256", "string"],
            //     tokenTransferMetadataBytes
            // );
            await ramp.connect(owner).updateChainIdWhitelist([31337], [2]);
            await ramp.connect(owner).addRampSender(addr1.address);

            const tx = await ramp.connect(addr1).sendRequest(targetChainId, mockRouter.address, ethers.utils.toUtf8Bytes(message), tokenAmount);
            await expect(tx)
                .to.emit(ramp, "RequestSent")
                .withArgs(
                    anyValue,
                    0,
                    addr1.address,
                    receiver,
                    sourceChainId,
                    targetChainId,
                    ethers.utils.toUtf8Bytes(message),
                    anyValue
                );
        });
    });

    describe("Transmit", () => {
        it("should pass when valid signatures are provided and forward the message", async function () {
            const { ramp, owner, addr1, mockRouter, wallet1, wallet2, wallet3 } = await loadFixture(deployRampFixture);
            const reportContext = getValidReportContext(mockRouter);
            const reportContextEncoded = ethers.utils.defaultAbiCoder.encode(
                [
                    "bytes32", "uint256", "uint256", "string", "address",
                ],
                [
                    reportContext.messageId,
                    reportContext.sourceChainId,
                    reportContext.targetChainId,
                    reportContext.sender,
                    reportContext.receiver
                ]
            );

            const message = ethers.utils.toUtf8Bytes("Valid Message");
            const tokenAmount = getValidTokenAmount();
            const tokenAmountEncoded = ethers.utils.defaultAbiCoder.encode(
                [
                    "uint256", "string", "string", "uint256", "bytes"
                ],
                [
                    tokenAmount.targetChainId,
                    tokenAmount.tokenAddress,
                    tokenAmount.symbol,
                    tokenAmount.amount,
                    tokenAmount.extraData,
                ]
            );

            console.log("Report Hash (Test):", reportContextEncoded);
            console.log("Message Hash (Test):", message);
            console.log("TokenAmount Hash (Test):", tokenAmountEncoded);

            const reportHash = generateReportBytesHash(reportContextEncoded, message, tokenAmountEncoded);
            const { rs, ss, rawVs } = generateSigns(reportHash, [wallet1.privateKey, wallet2.privateKey, wallet3.privateKey]);

            await ramp.connect(owner).updateChainIdWhitelist([1], [2]);
            const tx = await ramp.connect(addr1).transmit(reportContextEncoded, message, tokenAmountEncoded, rs, ss, rawVs);

            await expect(tx).to.emit(ramp, "ForwardMessageCalled")
                .withArgs(
                    reportContext.messageId,
                    reportContext.sourceChainId,
                    reportContext.targetChainId,
                    reportContext.sender,
                    reportContext.receiver,
                    message
                );
        });

        it("should fail if insufficient valid signatures are provided", async function () {
            const { ramp, owner, addr1, mockRouter, wallet1 } = await loadFixture(deployRampFixture);
            const reportContext = getValidReportContext(mockRouter);
            const reportContextEncoded = ethers.utils.defaultAbiCoder.encode(
                [
                    "bytes32", "uint256", "uint256", "string", "address",
                ],
                [
                    reportContext.messageId,
                    reportContext.sourceChainId,
                    reportContext.targetChainId,
                    reportContext.sender,
                    reportContext.receiver
                ]
            );

            const message = ethers.utils.toUtf8Bytes("Invalid Message");
            const tokenAmount = getValidTokenAmount();
            const tokenAmountEncoded = ethers.utils.defaultAbiCoder.encode(
                [
                    "uint256", "string", "string", "uint256", "bytes"
                ],
                [
                    tokenAmount.targetChainId,
                    tokenAmount.tokenAddress,
                    tokenAmount.symbol,
                    tokenAmount.amount,
                    tokenAmount.extraData,
                ]
            );

            const reportHash = generateReportBytesHash(reportContextEncoded, message, tokenAmountEncoded);
            const { rs, ss, rawVs } = generateSigns(reportHash, [wallet1.privateKey]);

            await ramp.connect(owner).updateChainIdWhitelist([1], [2]);
            await expect(
                ramp.connect(addr1).transmit(reportContextEncoded, message, tokenAmountEncoded, rs, ss, rawVs)
            ).to.be.revertedWith('Insufficient or invalid signatures');
        });
    });

    function getValidReportContext(mockRouter) {
        return {
            messageId: ethers.utils.id("ValidRequest"),
            sourceChainId: 1,
            targetChainId: 2,
            sender: "0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0",
            receiver: mockRouter.address,
        };
    }

    function getValidTokenAmount() {
        return {
            targetChainId: 2,
            tokenAddress: "0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0",
            symbol: "ETH",
            amount: TOKEN_AMOUNT,
            extraData: ethers.utils.toUtf8Bytes("swapid"),
        };
    }

    function generateReportBytesHash(reportContextEncoded, message, tokenAmountEncoded) {
        return ethers.utils.keccak256(
            ethers.utils.defaultAbiCoder.encode(
                [
                    "bytes", // ReportContext
                    "bytes", // Message
                    "bytes", // TokenAmount
                ],
                [
                    reportContextEncoded,
                    message,
                    tokenAmountEncoded,
                ]
            )
        );
    }

    function generateSigns(hash, privateKeys) {
        var rs = [];
        var ss = [];
        let buffer = new Array(32);
        for (var i = 0; i < privateKeys.length; i++) {
            let signKey = new ethers.utils.SigningKey(privateKeys[i]);
            var Signature = signKey.signDigest(hash);
            rs.push(Signature.r);
            ss.push(Signature.s);
            var vv = Signature.v == 27 ? "00" : "01";
            buffer[i] = vv;
        }
        const rawVs = buildRawVs(buffer)
        return { rs, ss, rawVs };
    }

    function buildRawVs(buffer) {
        buffer.fill(0, 4);
        var v = Buffer.from(buffer);
        const bufferAsString = v.toString('hex');
        const signatureV = "0x" + bufferAsString;
        // console.log("signature V:", signatureV)
        return signatureV;
    }
})