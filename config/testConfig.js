
var FlightSuretyApp = artifacts.require("FlightSuretyApp");
var FlightSuretyData = artifacts.require("FlightSuretyData");
var BigNumber = require('bignumber.js');

var Config = async function(accounts) {
    
    // These test addresses are useful when you need to add
    // multiple users in test scripts
    let testAddresses = [
        "0x071de903f003F31476d25bcAf621b5E1251e0B22",
        "0x14125aDcd80323f58aeb841429C7FeD9B1720049",
        "0xe232c61614097147619af532Eb3aD0dd80Df693f",
        "0xdB631828274B2397086F38dEf0068Be415970A41",
        "0x4619C23B652312e073e745B2311d38646C1ab9DD",
        "0x1691C83aBa94E3b55A8A449201060f784cdf25f2",
        "0xDc81f9bd7C8a0fE6099DDC36b5847239fB719E68",
        "0xfb19699322b797cAA73EB4B0F962380eB2417558",
        "0x127eB438D0A5e2843364D8627998067897bF787A"
    ];


    let owner = accounts[0];
    let firstAirline = accounts[1];

    let flightSuretyData = await FlightSuretyData.new();
    let flightSuretyApp = await FlightSuretyApp.new(flightSuretyData.address);

    
    return {
        owner: owner,
        firstAirline: firstAirline,
        weiMultiple: (new BigNumber(10)).pow(18),
        testAddresses: testAddresses,
        flightSuretyData: flightSuretyData,
        flightSuretyApp: flightSuretyApp
    }
}

module.exports = {
    Config: Config
};