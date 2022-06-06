
var Test = require('../config/testConfig.js');
var BigNumber = require('bignumber.js');

contract('Flight Surety Tests', async (accounts) => {

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
        passengers = accounts.slice(6, 9);

        await config.flightSuretyData.setOperatingStatus(true, { from: owner });
        await app.registerAirline('Airline 1', airline1, { from: owner });
        await data.authorizeCaller(airline1, { from: owner });

    });

    /****************************************************************************************/
    /* Operations and Settings                                                              */
    /****************************************************************************************/

    it(`(multiparty) has correct initial isOperational() value`, async function () {

        // Get operating status
        let status = await config.flightSuretyData.isOperational.call();
        assert.equal(status, true, "Incorrect initial operating status value");

    });

    it(`(multiparty) can block access to setOperatingStatus() for non-Contract Owner account`, async function () {

        // Ensure that access is denied for non-Contract Owner account
        let accessDenied = false;
        try {
            await config.flightSuretyData.setOperatingStatus(false, { from: config.testAddresses[2] });
        }
        catch (e) {
            accessDenied = true;
        }
        assert.equal(accessDenied, true, "Access not restricted to Contract Owner");

    });

    it(`(multiparty) can allow access to setOperatingStatus() for Contract Owner account`, async function () {

        // Ensure that access is allowed for Contract Owner account
        let accessDenied = false;
        try {
            await config.flightSuretyData.setOperatingStatus(false);
        }
        catch (e) {
            accessDenied = true;
        }
        assert.equal(accessDenied, false, "Access not restricted to Contract Owner");

    });

    it(`(multiparty) can block access to functions using requireIsOperational when operating status is false`, async function () {

        await config.flightSuretyData.setOperatingStatus(false);

        let reverted = false;
        try {
            await config.flightSurety.setTestingMode(true);
        }
        catch (e) {
            reverted = true;
        }
        assert.equal(reverted, true, "Access not blocked for requireIsOperational");

        // Set it back for other tests to work
        await config.flightSuretyData.setOperatingStatus(true);

    });

    /****************************************************************************************/
    /* Airlines                                                                             */
    /****************************************************************************************/
    describe('Airlines', () => {

        it('(airline) cannot register another Airline using registerAirline() if it is not funded', async () => {
            // ARRANGE
            let newAirline = accounts[2];

            // ACT
            try {
                await app.registerAirline("New Airline", newAirline, { from: airline1 });
            }
            catch (e) {
                console.log(`\tFlight ${newAirline} registeration failed with : ${e}`);
            }

            let result = await app.isAirlineRegistered.call(newAirline);

            // ASSERT
            assert.equal(result, false, "Airline should not be able to register another airline if it hasn't provided funding");
        });

        it('Only existing airline may register a new airline until there are at least four airlines registered', async function () {
            let fundPrice = web3.utils.toWei("10", "ether");

            await app.fund({ from: airline1, value: fundPrice });
            let isAirline1Funded = await app.isAirlineFunded.call(airline1);
            console.log(`\tFlight isAirlineFunded resulted : ${isAirline1Funded}`);

            assert.equal(isAirline1Funded, true, "Airline1 couldn't be funded");

            await app.registerAirline("Airline 2", airline2, { from: airline1 });
            await app.registerAirline("Airline 3", airline3, { from: airline1 });
            await app.registerAirline("Airline 4", airline4, { from: airline1 });
            await app.registerAirline("Airline 5", airline5, { from: airline1 });

            isAirline2Registered = await app.isAirlineRegistered.call(airline2);
            isAirline3Registered = await app.isAirlineRegistered.call(airline3);
            isAirline4Registered = await app.isAirlineRegistered.call(airline4);
            isAirline5Registered = await app.isAirlineRegistered.call(airline5);

            assert.equal(isAirline2Registered, true, "isAirline2Registered An existing airline may register new airlines until there are at least 4 registered airlines");
            assert.equal(isAirline3Registered, true, "isAirline3Registered An existing airline may register new airlines until there are at least 4 registered airlines");
            assert.equal(isAirline4Registered, true, "isAirline4Registered An existing airline can't register new airlines if there are at least 4 registered airlines");
            assert.equal(isAirline5Registered, false, "isAirline5Registered An existing airline can't register new airlines if there are at least 4 registered airlines");
        });

        it('Registration of fifth and subsequent airlines requires multi-party consensus of 50% of registered airlines', async function () {
            let numberOfRegisteredAirlines = await app.airlineMembersLength.call();

            let fundPrice = web3.utils.toWei("10", "ether");
            await app.fund({ from: airline2, value: fundPrice });
            await app.fund({ from: airline3, value: fundPrice });
            await app.fund({ from: airline4, value: fundPrice });

            let isAirline2Funded = await app.isAirlineFunded.call(airline2);
            let isAirline3Funded = await app.isAirlineFunded.call(airline3);
            let isAirline4Funded = await app.isAirlineFunded.call(airline4);

            assert.equal(isAirline2Funded, true, "Airline 2 couldn't be funded");
            assert.equal(isAirline3Funded, true, "Airline 3 couldn't be funded");
            assert.equal(isAirline4Funded, true, "Airline 4 couldn't be funded");

            let registeringAirlines = [airline1, airline2, airline3, airline4];
            let isAirline5Registered = await app.isAirlineRegistered(airline5);
            assert.equal(isAirline5Registered, false, "Airline 5 should not be registered");

            let votes = 0;
            let i = 0;
            while (!isAirline5Registered) {
                await app.approveAirlineRegistration(airline5, true, { from: registeringAirlines[i] });
                let voteCounts = await app.getAirlineVoteCount.call(airline5);
                votes = voteCounts;
                await app.registerAirline("Airline 5", airline5, { from: registeringAirlines[i] });
                isAirline5Registered = await app.isAirlineRegistered(airline5);
                i++;
            }

            numberOfRegisteredAirlines = await app.airlineMembersLength.call();
            assert.equal(isAirline5Registered, true, "Airline 5 should be registered");
            assert.equal(numberOfRegisteredAirlines, 5, "multi-party consensus failed");
            assert.equal(votes, 2, "2 votes are required for registering airline 5");
        });

        it('Airline can register a flight', async () => {
            // Fund fifth airline 
            let fundPrice = web3.utils.toWei("10", "ether");
            await app.fund({ from: airline5, value: fundPrice });
            isAirline5Funded = await app.isAirlineFunded(airline5);

            assert.equal(isAirline5Funded, true, "Airline 5 couldn't be funded");

            // Register 5 flights by 5 airlines
            for (i = 0; i < flights.length; i++) {
                let airline = flights[i][0];
                let flightName = flights[i][1];
                let departureTime = flights[i][2];

                let tx = await app.registerFlight(flightName, departureTime, { from: airline });

                let registrationStatus = await app.isFlightRegistered.call(airline, flightName, departureTime);
                console.log(`\tFlight ${flightName} at ${departureTime} has been registered by ${airline}`);
                assert.equal(registrationStatus, true, "Flight couldn't be registered");
            }
        });
    });


    /****************************************************************************************/
    /* Passengers                                                                           */
    /****************************************************************************************/
    describe('Passengers', () => {

        it('Passengers can purchase flight insurance for up to 1 ether', async () => {
            let insuranceAmount = web3.utils.toWei("1", "ether");

            passengers.forEach(async (passenger, index) => {
                let flight = flights[index];
                let airline = flight[0];
                let flightName = flight[1];
                let departureTime = flight[2];

                let tx = await app.buy(airline, flightName, departureTime, { from: passenger, value: insuranceAmount });
                expectEvent(tx, 'InsurancePurchased', {
                    passenger: passenger,
                    amount: insuranceAmount
                });
            });
        });
    });

});
