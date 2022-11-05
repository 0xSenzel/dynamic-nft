require("@nomicfoundation/hardhat-toolbox");
require("@nomicfoundation/hardhat-chai-matchers");
require("@nomiclabs/hardhat-etherscan");
require("dotenv").config();

const GOERLI_URL = process.env.GOERLI_URL;
const PRIVATE_KEY = process.env.PRIVATE_KEY;
const API_KEY = process.env.API_KEY;

module.exports = {
  solidity: {
    compilers:[
      {
        version: "0.8.4",
      },
      {
        version: "0.6.4"
      },
      {
        version: "0.8.0",
      },
      ],
  },
  networks: {
    goerli: {
      url: GOERLI_URL,
      accounts: [PRIVATE_KEY]
    }
  },
  etherscan: {
    apiKey: API_KEY
  }
};
