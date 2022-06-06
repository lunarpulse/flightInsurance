
var Test = require('../config/testConfig.js');
//var BigNumber = require('bignumber.js');
const { expect } = require("chai");

const {
  BN,           
  expectEvent,  
  balance,
  ether,
} = require('@openzeppelin/test-helpers');

contract('Oracles', async (accounts) => {
  // Watch contract events
  const STATUS_CODE_UNKNOWN = 0;
  const STATUS_CODE_ON_TIME = 10;
  const STATUS_CODE_LATE_AIRLINE = 20;
  const STATUS_CODE_LATE_WEATHER = 30;
  const STATUS_CODE_LATE_TECHNICAL = 40;
  const STATUS_CODE_LATE_OTHER = 50;
  const TEST_ORACLES_COUNT = 20;
  const ORACLE_START_INDEX = 10;

  var config;
  before('setup contract', async () => {
    config = await Test.Config(accounts);
    data = config.flightSuretyData;
    app = config.flightSuretyApp;
    owner = accounts[0];
    airline1 = accounts[1];
    airline2 = accounts[2];
    airline3 = accounts[3];
    airline4 = accounts[4];
    airline5 = accounts[5];
    flights = [
      [airline1, 'OS 075', new Date(2021, 2, 27, 18, 30, 0).valueOf().toString()],
      [airline2, 'UPS 275', new Date(2021, 2, 28, 22, 0, 0).valueOf().toString()],
      [airline3, 'TK 1888', new Date(2021, 3, 10, 10, 0, 0).valueOf().toString()],
      [airline4, 'EW 7751', new Date(2021, 3, 12, 19, 0, 0).valueOf().toString()],
      [airline5, 'LX 1583', new Date(2021, 3, 14, 20, 0, 0).valueOf().toString()],
    ];

    oracles = accounts.slice(10, 10 + TEST_ORACLES_COUNT);
    MIN_ORACLE_RESPONSES = 3;

    await config.flightSuretyData.authorizeCaller(app.address);
    await app.registerAirline('Airline 1', airline1, { from: owner });
    await data.authorizeCaller(airline1, { from: owner });
  });

  describe('Oracles', () => {
    it('can register oracles', async () => {

      // ARRANGE
      let fee = await config.flightSuretyApp.REGISTRATION_FEE.call();

      // ACT
      for (let a = 0; a < TEST_ORACLES_COUNT; a++) {
        await config.flightSuretyApp.registerOracle({ from: accounts[a + ORACLE_START_INDEX], value: fee });
        let result = await config.flightSuretyApp.getMyIndexes.call({ from: accounts[a + ORACLE_START_INDEX] });
        console.log(`Oracle Registered: ${result[0]}, ${result[1]}, ${result[2]}`);
      }
    });

    it('can request flight status', async () => {

      // ARRANGE
      let flight = 'ND1309'; // Course number
      let timestamp = Math.floor(Date.now() / 1000);

      // Submit a request for oracles to get status information for a flight
      await config.flightSuretyApp.fetchFlightStatus(config.firstAirline, flight, timestamp);
      // ACT

      // Since the Index assigned to each test account is opaque by design
      // loop through all the accounts and for each account, all its Indexes (indices?)
      // and submit a response. The contract will reject a submission if it was
      // not requested so while sub-optimal, it's a good test of that feature
      for (let a = 1; a < TEST_ORACLES_COUNT; a++) {

        // Get oracle information
        let oracleIndexes = await config.flightSuretyApp.getMyIndexes.call({ from: accounts[a + ORACLE_START_INDEX] });
        for (let idx = 0; idx < 3; idx++) {

          try {
            // Submit a response...it will only be accepted if there is an Index match
            await config.flightSuretyApp.submitOracleResponse(oracleIndexes[idx], airline1, flight, timestamp, STATUS_CODE_ON_TIME, { from: accounts[a + ORACLE_START_INDEX] });

          }
          catch (e) {
            // Enable this when debugging
            console.log(`\nError => idx: ${idx}, oracleIndexes: ${oracleIndexes[idx]}, flight: ${flight}, timestamp: ${timestamp}`);
          }

        }
      }
    });

    it('If flight is delayed due to airline fault, insured passenger credit 150% of insured', async () => {
      let flight = flights[0];
      let airline = flight[0];      // First airline
      let flightName = flight[1];
      let departureTime = flight[2];


      let passenger = accounts[6];
      let fundPrice = web3.utils.toWei("10", "ether");
      let insuranceAmount = web3.utils.toWei("1", "ether");

      // Check: airline should be registered and not funded
      let isAirlineRegistered = await app.isAirlineRegistered.call(airline);
      assert.equal(isAirlineRegistered, true, 'Airline should be registered');
      let isAirlineFunded = await app.isAirlineFunded.call(airline);
      assert.equal(isAirlineFunded, false, 'Airline should not be funded');

      // fund airline
      await app.fund({ from: airline, value: fundPrice });
      isAirlineFunded = await app.isAirlineFunded.call(airline);
      assert.equal(isAirlineFunded, true, 'Airline should be funded');

      // Register flight
      await app.registerFlight(flightName, departureTime, { from: airline });
      let isFlightRegistered = await app.isFlightRegistered.call(airline, flightName, departureTime);
      assert.equal(isFlightRegistered, true, 'Flight is not registered');

      // passenger buys insurance for 1 ether
      await app.buy(airline, flightName, departureTime, { from: passenger, value: insuranceAmount });
      let amount = await app.getPremium(airline, flightName, departureTime, { from: passenger });
      assert.equal(amount, insuranceAmount, 'Passenger could not pay insurance');

      // Submit a request for oracles to get status information for a flight
      expectEvent(
        await app.fetchFlightStatus(airline, flightName, departureTime, {
          from: passenger,
        }),
        "OracleRequest",
        {
          airline: airline,
          flight: flightName,
          timestamp: departureTime,
        }
      );

      let reportedFlightStatus = STATUS_CODE_LATE_AIRLINE;
      let responses = 0;

      let promises = Promise.all(
        oracles.map(async (oracleAccount) => {
          let registered = await app.isOracleRegistered.call(oracleAccount);
          console.log(`\tFlight registered resulted : ${registered}, oracleAccount: ${oracleAccount}`);

          //expect(registered).to.be.true;

          let oracleIndexes = await app.getMyIndexes.call({
            from: oracleAccount,
          });
          expect(oracleIndexes).to.have.lengthOf(3);

          for (let i = 0; i < 3; i++) {
            try {
              await app.submitOracleResponse(
                oracleIndexes[i],
                airline,
                flightName,
                departureTime,
                reportedFlightStatus,
                { from: oracleAccount }
              );
              responses++;
            } catch (e) {
            }
          }
        })
      );
      await promises;
      expect(responses).to.be.gte(MIN_ORACLE_RESPONSES);

      //let isInsurancePaidOut = await app.isInsurancePaidOut(airline, flightName, departureTime, { from: passenger });
      //assert.equal(isInsurancePaidOut, true, "Insurance should be paid out due to airline delay");

      let actualCredit = await app.getPassengerCreditBalance({ from: passenger });
      const expectedCredit = (web3.utils.toBN(insuranceAmount)).mul(new BN(3)).div(new BN(2));
      console.log(`\tPassenger actual credit: ${actualCredit.toString()}. Passenger expected credit: ${expectedCredit.toString()}.`)
      assert.equal(actualCredit.eq(expectedCredit), true, `Credit to passenger is ${actualCredit.toString()} instead of ${expectedCredit.toString()}.`);
    });

    it("Passenger can withdraw insurance refund", async () => {
      let passenger = accounts[6];

      let passengerBalance = await app.getPassengerCreditBalance({ from: passenger });

      expect(passengerBalance).to.be.bignumber.equal(ether("1.5"));

      let tracker = await balance.tracker(passenger);

      expectEvent(
        await app.withdrawAllPassengerCredit({ from: passenger }),
        "Withdraw",
        {
          sender: passenger, amount: passengerBalance
        }
      );
      expect(await tracker.delta()).to.be.bignumber.gte(ether('1.499'));  //minus gas fees
    })
  });


});
