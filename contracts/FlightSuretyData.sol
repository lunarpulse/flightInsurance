// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "../node_modules/@openzeppelin/contracts/utils/math/SafeMath.sol";

contract FlightSuretyData {
    using SafeMath for uint256;

    /********************************************************************************************/
    /*                                       DATA VARIABLES                                     */
    /********************************************************************************************/

    address private contractOwner; // Account used to deploy contract
    bool private operational = true; // Blocks all state changes throughout the contract if false

    struct Airline {
        string name;
        bool isOperational;
        bool isRegistered;
        bool isFunded;
    }

    mapping(address => Airline) airlines;

    struct Insurance {
        uint256 premium;
        address payable insuree;
        bool validity;
    }

    struct Fund {
        address fundraiser;
        uint256 amount;
    }
    mapping(address => Fund) airlineFund;

    mapping(address => bool) public authorizedCallers;
    address[] airlineMembers = new address[](0);

    struct Commitee {
        bool status;
    }
    mapping(address => uint256) private airlineVotes;
    mapping(address => Commitee) airlineCommitee;

    mapping(address => mapping(string => mapping(uint256 => address[])))
        private flightSchedulePassengerListMap; // airline name, flight name, timestamp => passenger array

    mapping(address => mapping(string => mapping(uint256 => bytes32)))
        private flightScheduleKeyMap; // airline name, flight name, timestamp => passenger array
    mapping(bytes32 => address[]) private flightScheduleKeyPassengersMap; // flight schedule key to passengers

    mapping(address => mapping(string => mapping(uint256 => mapping(address => bytes32)))) InsuranceKeyMap; // airline name, flight name, timestamp, passenger address getkey with all those params and store the key
    mapping(bytes32 => Insurance) private insuranceStorage; // Insurance key to Insurance

    mapping(address => bytes32[]) private passengerInsurancesMap; // airline name, flight name, timestamp, passenger address getkey with all those params and store the key

    mapping(address => uint256) passengerCreditBalance; // passenger addr to credit they can widthraw

    /********************************************************************************************/
    /*                                       EVENT DEFINITIONS                                  */
    /********************************************************************************************/

    event AuthorizedContract(address targetContractAddress);
    event DeAuthorizedContract(address targetContractAddress);

    /**
     * @dev Constructor
     *      The deploying account becomes contractOwner
     */
    constructor() public {
        contractOwner = msg.sender;
    }

    /********************************************************************************************/
    /*                                       FUNCTION MODIFIERS                                 */
    /********************************************************************************************/

    // Modifiers help avoid duplication of code. They are typically used to validate something
    // before a function is allowed to be executed.

    /**
     * @dev Modifier that requires the "operational" boolean variable to be "true"
     *      This is used on all state changing functions to pause the contract in
     *      the event there is an issue that needs to be fixed
     */
    modifier requireIsOperational() {
        require(operational, "Contract is currently not operational");
        _; // All modifiers require an "_" which indicates where the function body will be added
    }

    /**
     * @dev Modifier that requires the "ContractOwner" account to be the function caller
     */
    modifier requireContractOwner() {
        require(msg.sender == contractOwner, "Caller is not contract owner");
        _;
    }

    /**
     * @dev Modifier that requires the "ContractOwner" account to be the function caller
     */
    modifier requireAirlineRegistered(address airline) {
        require(airlines[airline].isRegistered, "Airline was not registered");
        _;
    }

    /**
     * @dev Modifier that requires the "ContractAddress" account to be authorized
     */
    modifier requireCallerAddressAuthorized() {
        require(
            authorizedCallers[msg.sender],
            "ContractAddress is not authorized"
        );
        _;
    }

    /********************************************************************************************/
    /*                                       UTILITY FUNCTIONS                                  */
    /********************************************************************************************/

    /**
     * @dev Get operating status of contract
     *
     * @return A bool that is the current operating status
     */
    function isOperational() public view returns (bool) {
        return operational;
    }

    /**
     * @dev Sets contract operations on/off
     *
     * When operational mode is disabled, all write transactions except for this one will fail
     */
    function setOperatingStatus(bool mode) external requireContractOwner {
        operational = mode;
    }

    function authorizeCaller(address caller)
        external
        requireContractOwner
        requireIsOperational
    {
        authorizedCallers[caller] = true;
        emit AuthorizedContract(caller);
    }

    function deAuthorizeCaller(address caller) external requireContractOwner {
        delete authorizedCallers[caller];
        emit DeAuthorizedContract(caller);
    }

    /********************************************************************************************/
    /*                                     SMART CONTRACT FUNCTIONS                             */
    /********************************************************************************************/
    function setAirlineMembers(address airlineMember) private {
        airlineMembers.push(airlineMember);
    }

    function getAirlineMembers() external view returns (address[] memory) {
        return airlineMembers;
    }

    function airlineMembersLength()
        external
        view
        requireIsOperational
        returns (uint256)
    {
        return airlineMembers.length;
    }

    function getAirlineOperationStatus(address airlineAddr)
        external
        view
        requireIsOperational
        returns (bool)
    {
        return airlines[airlineAddr].isOperational;
    }

    function getAirlineRegistrationStatus(address airlineAddr)
        external
        view
        requireIsOperational
        returns (bool)
    {
        return airlines[airlineAddr].isRegistered;
    }

    function setAirlineRegistrationStatus(address airlineAddr, bool status)
        internal
        requireIsOperational
    {
        airlines[airlineAddr].isRegistered = status;
    }

    function resetVoteCounter(address account) external requireIsOperational {
        delete airlineVotes[account];
    }

    function getCommiteeStatus(address commitee)
        external
        view
        requireIsOperational
        returns (bool)
    {
        return airlineCommitee[commitee].status;
    }

    function getAirlineVoteCount(address airlineAddr)
        external
        view
        returns (uint256)
    {
        return airlineVotes[airlineAddr];
    }

    function addCommitees(address commitee) external {
        airlineCommitee[commitee] = Commitee({status: true});
    }

    function voteAirlineRegistration(address airline) external {
        uint256 vote = airlineVotes[airline];
        airlineVotes[airline] = vote.add(1);
    }

    /*
     * @dev purchaseInsurance, called by passenger
     *
     * @return none
     */
    function purchaseInsurance(
        address airline,
        string calldata flight,
        uint256 timestamp,
        address passengerAddr,
        uint256 claimableAmount
    ) external requireIsOperational {
        bytes32 flightKey = getFlightKey(airline, flight, timestamp);
        flightScheduleKeyMap[airline][flight][timestamp] = flightKey;
        flightScheduleKeyPassengersMap[flightKey].push(passengerAddr);
        bytes32 insuranceKey = keccak256(
            abi.encodePacked(airline, flight, timestamp, passengerAddr)
        );
        InsuranceKeyMap[airline][flight][timestamp][
            passengerAddr
        ] = insuranceKey;
        passengerInsurancesMap[passengerAddr].push(insuranceKey);
        insuranceStorage[insuranceKey] = Insurance({
            insuree: payable(passengerAddr),
            premium: claimableAmount,
            validity: true
        });

        uint256 currentAirlineFund = airlineFund[airline].amount;
        airlineFund[airline].amount = currentAirlineFund.add(claimableAmount);
    }

    function fundAirline(address airlineAddr, uint256 amount) public {
        airlineFund[airlineAddr] = Fund({
            fundraiser: airlineAddr,
            amount: amount
        });
        airlineFund[airlineAddr].amount = airlineFund[airlineAddr].amount.add(
            amount
        );

        airlines[airlineAddr].isFunded = true;
        airlines[airlineAddr].isOperational = true;
    }

    function getAirlineFunding(address airlineAddr)
        external
        view
        returns (uint256)
    {
        return airlineFund[airlineAddr].amount;
    }

    /**
     * @dev Add an airline to the registration queue
     *      Can only be called from FlightSuretyApp contract
     *
     */
    function registerAirline(
        string calldata name,
        address airlineAddr,
        bool _isOperational
    ) external requireIsOperational {
        airlines[airlineAddr] = Airline({
            name: name,
            isOperational: _isOperational,
            isRegistered: true,
            isFunded: false
        });

        authorizedCallers[airlineAddr] = true;
        setAirlineMembers(airlineAddr);
    }

    function isAirlineRegistered(address account) external view returns (bool) {
        return airlines[account].isRegistered;
    }

    function isAirlineFunded(address account) external view returns (bool) {
        return airlines[account].isFunded;
    }

    /**
     * @dev Buy insurance for a flight
     *
     */
    function buy() external payable {}

    /**
     *  @dev Credits payouts to insurees whose insurance matches getFlightKey(airline, flight, timestamp)
     */
    function creditInsurees(
        address airline,
        string memory flight,
        uint256 timestamp,
        uint256 payOffNumerator,
        uint256 payOffDenominator
    ) external requireCallerAddressAuthorized {
        // get flight key
        bytes32 flightKey = getFlightKey(airline, flight, timestamp);
        // this flight done bool false check and short return here
        uint256 insureeCount = flightScheduleKeyPassengersMap[flightKey].length;
        // loop on insurees
        for (uint256 i = 0; i < insureeCount; i++) {
            // address of insuree
            address insureeAddr = flightScheduleKeyPassengersMap[flightKey][i];
            // multiply paid premium by payOff
            bytes32 insuranceKey = keccak256(
                abi.encodePacked(airline, flight, timestamp, insureeAddr)
            );
            if (insuranceStorage[insuranceKey].validity == true) {
                uint256 payout = (insuranceStorage[insuranceKey].premium)
                    .mul(payOffNumerator)
                    .div(payOffDenominator);
                uint256 airlineFundAmount = airlineFund[airline].amount;
                require(airlineFundAmount>payout, "insufficient fund for this airline" );

                insuranceStorage[insuranceKey].validity = false;
                // remove fund
                airlineFund[airline].amount = airlineFundAmount.sub(payout);
                // update insuree credit
                passengerCreditBalance[insureeAddr] = passengerCreditBalance[insureeAddr].add(
                    payout
                );
            }
        }
    }


    /**
     *  @dev Transfers passengers paid premia to insurance definitely (because flight was not delayed due to an airline fault)
     *
     */
    function terminateInsurance(
        address airline,
        string memory flight,
        uint256 timestamp
    ) external requireCallerAddressAuthorized {
        // get flight key
        bytes32 flightKey = getFlightKey(airline, flight, timestamp);
        uint256 insureeCount = flightScheduleKeyPassengersMap[flightKey].length;
        // loop on insurees
        for (uint256 i = 0; i < insureeCount; i++) {
            // address of insuree
            address insureeAddr = flightScheduleKeyPassengersMap[flightKey][i];
            // multiply paid premium by payOff
            bytes32 insuranceKey = keccak256(
                abi.encodePacked(airline, flight, timestamp, insureeAddr)
            );
            insuranceStorage[insuranceKey].validity = false;
            //delete insuranceStorage[flightKey][i];
        }
    }

    /**
     * @dev Initial funding for the insurance. Unless there are too many delayed flights
     *      resulting in insurance payouts, the contract should be self-sustaining
     *
     */
    function fund() public payable {}

    function getFlightKey(
        address airline,
        string memory flight,
        uint256 timestamp
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(airline, flight, timestamp));
    }

    fallback() external payable {
        fundAirline(msg.sender, msg.value);
    }

    receive() external payable {
        fundAirline(msg.sender, msg.value);
    }

    /**
     *  @dev Transfers eligible payout funds to insuree
     *
     */
    function withdrawPassengerCredit(address passengerAddr)
        external
        requireIsOperational
        requireCallerAddressAuthorized
        returns (uint256)
    {
        uint256 amount = passengerCreditBalance[passengerAddr];
        passengerCreditBalance[passengerAddr] = 0;
        delete passengerCreditBalance[passengerAddr];
        return amount;
    }

    function getPassengerCreditBalance(address passengerAddr)
        external
        view
        requireIsOperational
        returns (uint256)
    {
        return passengerCreditBalance[passengerAddr];
    }

    /**
     *  @dev Returns paid insurance premium by flight info
     *
     */
    function getPremium(
        address airlineAddr,
        string calldata flight,
        uint256 departureTime,
        address passengerAddr
    ) external view requireCallerAddressAuthorized returns (uint256) {
        bytes32 flightKey = getFlightKey(airlineAddr, flight, departureTime);
        uint256 insureeCount = flightScheduleKeyPassengersMap[flightKey].length;
        // loop on insurees
        uint256 amount = 0;
        for (uint256 i = 0; i < insureeCount; i++) {
            // address of insuree
            address insureeAddr = flightScheduleKeyPassengersMap[flightKey][i];
            bytes32 insuranceKey = keccak256(
                abi.encodePacked(
                    airlineAddr,
                    flight,
                    departureTime,
                    insureeAddr
                )
            );
            if (insureeAddr == passengerAddr) {
                amount = insuranceStorage[insuranceKey].premium;
            }
        }
        return amount;
    }
}
