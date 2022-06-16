var HDWalletProvider = require("truffle-hdwallet-provider");
var mnemonic = "offer write sand beyond wolf case country idle since wool deposit wise";

module.exports = {
  networks: {
    development: {
      provider: function() {
        return new HDWalletProvider(mnemonic, "http://localhost:8545/", 0, 50);
      },
      network_id: '*',
      gasPrice: 10000000, 
      gasLimit: 3141592000000   
    },
    rinkeby: {
      provider: () => new HDWalletProvider(mnemonic, `https://rinkeby.infura.io/v3/${infuraKey}`),
      network_id: 4,       // rinkeby's id
      gas: 5500000,        // rinkeby has a lower block limit than mainnet
      confirmations: 2,
      timeoutBlocks: 200,
      skipDryRun: true,
    }
  },
  plugins: ["truffle-contract-size"],
  // Configure your compilers
  compilers: {
    solc: {
      version: "0.8.13",    // Fetch exact version from solc-bin (default: truffle's version)
      docker: false,        // Use "0.5.1" you've installed locally with docker (default: false)
      settings: {          // See the solidity docs for advice about optimization and evmVersion
       optimizer: {
         enabled: true,
         runs: 200
       },
       evmVersion: "london"
      }
    },
  },
};