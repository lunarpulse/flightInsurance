import FlightSuretyApp from '../../build/contracts/FlightSuretyApp.json';
import FlightSuretyData from '../../build/contracts/FlightSuretyData.json';
import Config from './config.json';
import Web3 from 'web3';

var BigNumber = require('bignumber.js');

export default class Contract {
	constructor(network, callback) {

		let config = Config[network];
		this.web3 = new Web3(new Web3.providers.HttpProvider(config.url));
		this.flightSuretyApp = new this.web3.eth.Contract(FlightSuretyApp.abi, config.appAddress);
		this.flightSuretyData = new this.web3.eth.Contract(FlightSuretyData.abi, config.dataAddress);
		this.initialize(callback);
		this.weiMultiple = (new BigNumber(10)).pow(18);
		this.owner = null;
		this.airlines = [];
		this.passengers = [];
		this.oracles = [];
		this.price = null;
		this.fund_fee = 10;
		this.flights = new Map();

		this.CREDIT_MULTIPLIER = 1.5;
		// Watch contract events
		const STATUS_CODE_UNKNOWN = 0;
		const STATUS_CODE_ON_TIME = 10;
		const STATUS_CODE_LATE_AIRLINE = 20;
		const STATUS_CODE_LATE_WEATHER = 30;
		const STATUS_CODE_LATE_TECHNICAL = 40;
		const STATUS_CODE_LATE_OTHER = 50;

		this.STATUS_CODES = Array(STATUS_CODE_UNKNOWN, STATUS_CODE_ON_TIME, STATUS_CODE_LATE_AIRLINE, STATUS_CODE_LATE_WEATHER, STATUS_CODE_LATE_TECHNICAL, STATUS_CODE_LATE_OTHER);
		this.transaction_passenger = null;
		this.transaction_airline = null;
	}

	makeid() {
		var text = "";
		var possible = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789";
	  
		for (var i = 0; i < 5; i++)
		  text += possible.charAt(Math.floor(Math.random() * possible.length));
	  
		return text;
	}

	initialize(callback) {
		this.web3.eth.getAccounts((error, accounts) => {
			let flightNames = [];

			const url = 'http://localhost:3000/flights';  //our url here

			fetch(url)
				.then(
					function (response) {
						if (response.status !== 200) {
							console.warn('Looks like there was a problem. Status Code: ' + response.status);
							return;
						}
	
						// Examine the text in the response  
						response.json().then(function (data) {
							let option;
							data = data.result
							for (let i = 0; i < data.length; i++) {
								flightNames.push(data[i].name);
							}
						});
					}
				)
				.catch(function (err) {
					console.error('Fetch Error -', err);
				});

			this.owner = accounts[0];

			function delay(time) {
				return new Promise(resolve => setTimeout(resolve, time));
			}

			delay(1000).then(() => {
				let counter = 1;
	
				while (this.airlines.length < 5) {
					// Register the airlines
					this.registerAirline(flightName, accounts[counter]);
					this.airlines.push(accounts[counter]);
					this.flights.set(accounts[counter], flightNames[counter]);

					console.log("flightNames[",counter,"]", flightNames[counter]);
					console.log("this.flights.get(", accounts[counter],")", this.flights.get(accounts[counter]));
					counter++;

				}
				// Fund this airline to be used in the project.
				this.fund(this.airlines[2]);
	
	
				while (this.passengers.length < 5) {
					console.log("passengers[",counter,"]", accounts[counter]);
					this.passengers.push(accounts[counter++]);
				}
	
				callback();
			});


		});
	}

	registerAirline(name,airlineAddress) {
		let self = this;
		self.flightSuretyApp.methods
			.registerAirline(name,airlineAddress)
			.send({ from: this.owner }, (error, result) => {

			});
	}
	fund(airlineAddress) {
		let self = this;
		let fee = this.weiMultiple * this.fund_fee;

		self.flightSuretyApp.methods
			.fund()
			.send({ from: airlineAddress, value: fee }, (error, result) => {

			});

	}

	submitOracleResponse(indexes, airline, flight, timestamp, callback) {
		let self = this;


		let payload = {
			indexes: indexes,
			airline: self.airlines[2],
			flight: flight,
			timestamp: timestamp,
			statusCode: self.STATUS_CODES[Math.floor(Math.random() * self.STATUS_CODES.length)]
		}
		self.flightSuretyApp.methods
			.triggerOracleResponse(payload.indexes, payload.airline, payload.flight, payload.timestamp, payload.statusCode)
			.send({ from: self.owner }, (error, result) => {
				callback(error, payload);

			});

	}


	isOperational(callback) {
		let self = this;
		self.flightSuretyApp.methods
			.isOperational()
			.call({ from: self.owner }, callback);
	}

	fetchFlightStatus(flight, departureDate, callback) {
		let self = this;
		let payload = {
			airline: self.airlines[2],
			flight: flight,
			//timestamp: Math.floor(Date.now() / 1000)
			timestamp: Date.parse(departureDate.toString()) / 1000
		}
		self.flightSuretyApp.methods
			.fetchFlightStatus(payload.airline, payload.flight, payload.timestamp)
			.send({ from: self.owner }, (error, result) => {
				callback(error, payload);
			});
	}

	buy(price, departureDate, callback) {
		let self = this;
		self.price = Number(price);
		let payload = {
			airline: self.airlines[2],
			passenger: self.passengers[1],
			price_wei: self.weiMultiple * price, //  Web3.utils.toWei(price.toString(), "ether")
		}
		self.flightSuretyApp.methods
			.buy(payload.airline, this.flights.get(payload.airline), Date.parse(departureDate) / 1000)
			.send({ from: payload.passenger, value: payload.price_wei }, (error, result) => {
				callback(error, payload);
			});
	}

	withdraw(callback) {
		let self = this;
		let payload = {
			airline: self.airlines[2],
			passenger: self.passengers[1]
		}
		self.flightSuretyApp.methods
			.withdrawAllPassengerCredit()
			.send({ from: payload.passenger }, (error, result) => {
				callback(error, payload);
			});

	}
}

