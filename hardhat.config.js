require('solidity-coverage');
require("@nomiclabs/hardhat-etherscan");
require('hardhat-contract-sizer');
require("@nomicfoundation/hardhat-toolbox");

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: "0.8.9",
  networks: {
    hardhat: {},
  },
};