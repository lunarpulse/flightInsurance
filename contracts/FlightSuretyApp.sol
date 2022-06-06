// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

// It's important to avoid vulnerabilities due to numeric overflow bugs
// OpenZeppelin's SafeMath library, when used correctly, protects agains such bugs
// More info: https://www.nccgroup.trust/us/about-us/newsroom-and-events/blog/2018/november/smart-contract-insecurity-bad-arithmetic/

import "../node_modules/@openzeppelin/contracts/utils/math/SafeMath.sol";

/************************************************** */
/* FlightSurety Smart Contract                      */
/************************************************** */
contract FlightSuretyApp {
    using SafeMath for uint256; // Allow SafeMath functions to be called for all uint256 types (similar to "prototype" in Javascript)

    /********************************************************************************************/
    /*                                       DATA VARIABLES                                     */
    /********************************************************************************************/

    // Flight status codees
    uint8 private constant STATUS_CODE_UNKNOWN = 0;
    uint8 private constant STATUS_CODE_ON_TIME = 10;
    uint8 private constant STATUS_CODE_LATE_AIRLINE = 20;
    uint8 private constant STATUS_CODE_LATE_WEATHER = 30;
    uint8 private constant STATUS_CODE_LATE_TECHNICAL = 40;
    uint8 private constant STATUS_CODE_LATE_OTHER = 50;

    address private contractOwner; // Account used to deploy contract
    bool private operational = true;

    struct Flight {
        bool isRegistered;
        uint8 statusCode;
        uint256 updatedTimestamp;
        address airline;
        string flight;
    }
    mapping(bytes32 => Flight) private flights; // airline address to flgiths

    uint256 constant voteThreshold = 4;
    bool private voteStatus = false;

    FlightSuretyData flightSuretyData; // Instance of FlightSuretyData
    address payable dataContractAddress;
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
        // Modify to call data contract's status
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
     * @dev Modifier that requires airline to be funded
     */
    modifier requireAirlineIsFunded(address airlineAddr) {
        require(
            flightSuretyData.isAirlineFunded(airlineAddr) ||
                msg.sender == contractOwner,
            "Airline is not funded"
        );
        _;
    }

    /********************************************************************************************/
    /*                                       CONSTRUCTOR                                        */
    /********************************************************************************************/

    /**
     * @dev Contract constructor
     *
     */
    constructor(address payable dataContract) public {
        contractOwner = msg.sender;
        dataContractAddress = dataContract;
        flightSuretyData = FlightSuretyData(dataContract);
    }

    /********************************************************************************************/
    /*                                       UTILITY FUNCTIONS                                  */
    /********************************************************************************************/

    function isOperational() public view returns (bool) {
        return operational; // Modify to call data contract's status
    }

    /********************************************************************************************/
    /*                                     SMART CONTRACT FUNCTIONS                             */
    /********************************************************************************************/

    /**
     * @dev Add an airline to the registration queue
     *
     */
    function registerAirline(string calldata name, address airlineAddr)
        external
        requireIsOperational
        requireAirlineIsFunded(msg.sender)
        returns (bool success, uint256 votes)
    {
        require(airlineAddr != address(0), "account address invalid");
        require(
            !flightSuretyData.getAirlineRegistrationStatus(airlineAddr),
            "Airline in the registration queue"
        );

        /*         require(
            flightSuretyData.getAirlineOperationStatus(airlineAddr),
            "Airline is not operational"
        ); */

        uint256 airlineMembers_Length = flightSuretyData.airlineMembersLength();
        success = false;
        votes = 0;
        if (airlineMembers_Length < voteThreshold) {
            flightSuretyData.registerAirline(name, airlineAddr, false);

            emit RegisterAirline(airlineAddr);
            success = true;
            votes = flightSuretyData.getAirlineVoteCount(airlineAddr);
            //return (true, airlineVotes);
        } else {
            if (voteStatus) {
                uint256 airlineVotes = flightSuretyData.getAirlineVoteCount(
                    airlineAddr
                );
                if (airlineVotes >= airlineMembers_Length / 2) {
                    flightSuretyData.registerAirline(name, airlineAddr, false);
                    voteStatus = false;
                    flightSuretyData.resetVoteCounter(airlineAddr);
                    emit RegisterAirline(airlineAddr);
                    success = true;
                    //return (true, 0);
                }
            }
        }
        //return (false, 0);
    }

    function approveAirlineRegistration(address airlineAddr, bool airlineVote)
        public
        requireIsOperational
    {
        require(
            !flightSuretyData.getAirlineRegistrationStatus(airlineAddr),
            "airline already registered"
        );
        require(
            flightSuretyData.getAirlineOperationStatus(msg.sender),
            "airline not operational"
        );

        if (airlineVote == true) {
            // Check and avoid duplicate vote for the same airline
            bool isDuplicate = false;
            isDuplicate = flightSuretyData.getCommiteeStatus(msg.sender);

            // Check to avoid registering same airline multiple times
            require(!isDuplicate, "Caller has already voted.");
            flightSuretyData.addCommitees(msg.sender);
            flightSuretyData.voteAirlineRegistration(airlineAddr);
        }
        voteStatus = true;
    }

    /**
     * @dev Register a future flight for insuring.
     *
     */
    function registerFlight(string calldata flight, uint256 departureTime)
        external
        requireIsOperational
        requireAirlineIsFunded(msg.sender)
    {
        bytes32 key = getFlightKey(msg.sender, flight, departureTime);
        flights[key] = Flight({
            airline: msg.sender,
            flight: flight,
            isRegistered: true,
            updatedTimestamp: departureTime,
            statusCode: STATUS_CODE_UNKNOWN
        });

        emit FlightRegistered(msg.sender, flight);
    }

    function getPayOutAmount() external view returns (uint256) {
        return flightSuretyData.getPassengerCreditBalance(msg.sender);
    }

    /**
     * @dev Called after oracle has updated flight status
     *
     */
    function processFlightStatus(
        address airlineAddr,
        string memory flight,
        uint256 timestamp,
        uint8 statusCode
    ) private requireIsOperational {
        //Insurance[] memory insuranceData = flightSuretyData.getPassengerInsuranceRecordsByAirline(airlineAddr);
        // do some calculation average or median of oracle results
        if (statusCode == STATUS_CODE_LATE_AIRLINE) {
            flightSuretyData.creditInsurees(
                airlineAddr,
                flight,
                timestamp,
                3,
                2
            );
        } else {
            flightSuretyData.terminateInsurance(airlineAddr, flight, timestamp);
        }
    }

    // Generate a request for oracles to fetch flight information
    function fetchFlightStatus(
        address airline,
        string calldata flight,
        uint256 timestamp
    ) external requireIsOperational {
        uint8 index = getRandomIndex(msg.sender);

        // Generate a unique key for storing the request
        bytes32 key = keccak256(
            abi.encodePacked(index, airline, flight, timestamp)
        );

        ResponseInfo storage r = oracleResponses[key];
        r.requester = msg.sender;
        r.isOpen = true;

        emit OracleRequest(index, airline, flight, timestamp);
    }

    fallback() external payable {
        fund();
    }

    receive() external payable {
        fund();
    }

    function fund() public payable requireIsOperational {
        require(msg.value >= 10 ether, "At least 10 Ether");
        require(
            !flightSuretyData.getAirlineOperationStatus(msg.sender),
            "Airline is already funded"
        );

        flightSuretyData.fundAirline(msg.sender, msg.value);
        emit AirlineFunded(msg.sender, msg.value);
    }

    function buy(
        address airlineAddr,
        string calldata flight,
        uint256 timestamp
    ) external payable requireIsOperational {
        require(
            flightSuretyData.getAirlineOperationStatus(airlineAddr),
            "Airline not operational"
        );

        require(
            (msg.value > 0 ether) && (msg.value <= 1 ether),
            "Passengers can only buy an insurance of more than 0 ether and less than 1 ether"
        );

        flightSuretyData.purchaseInsurance(
            airlineAddr,
            flight,
            timestamp,
            msg.sender,
            msg.value
        );
        emit InsurancePurchased(airlineAddr, msg.sender, msg.value);
    }

    function getPassengerCreditBalance() external view returns (uint256) {
        return flightSuretyData.getPassengerCreditBalance(msg.sender);
    }

    function withdrawAllPassengerCredit() public payable requireIsOperational {
        require(
            flightSuretyData.getPassengerCreditBalance(msg.sender) > 0,
            "No balance to withdraw"
        );
        uint256 withdrawAmount = flightSuretyData.withdrawPassengerCredit(msg.sender);
        payable(msg.sender).transfer(withdrawAmount);
        emit Withdraw(msg.sender, withdrawAmount);
    }

    /**
     *  @dev Returns paid insurance premium by flight info
     *
     */
    function getPremium(
        address airline,
        string calldata flight,
        uint256 departureTime
    ) external view returns (uint256) {
        return
            flightSuretyData.getPremium(
                airline,
                flight,
                departureTime,
                msg.sender
            );
    }

    // region ORACLE MANAGEMENT

    // Incremented to add pseudo-randomness at various points
    uint8 private nonce = 42;

    // Fee to be paid when registering oracle
    uint256 public constant REGISTRATION_FEE = 1 ether;

    // Number of oracles that must respond for valid status
    uint256 private constant MIN_RESPONSES = 3;

    struct Oracle {
        bool isRegistered;
        uint8[3] indexes;
    }

    // Track all registered oracles
    mapping(address => Oracle) private oracles;

    // Model for responses from oracles
    struct ResponseInfo {
        address requester; // Account that requested status
        bool isOpen; // If open, oracle responses are accepted
        mapping(uint8 => address[]) responses; // Mapping key is the status code reported
        // This lets us group responses and identify
        // the response that majority of the oracles
    }

    // Track all oracle responses
    // Key = hash(index, flight, timestamp)
    mapping(bytes32 => ResponseInfo) private oracleResponses;

    // Event fired each time an oracle submits a response

    event FlightRegistered(address indexed airline, string flight);
    event RegisterAirline(address account);
    event InsurancePurchased(address airline, address sender, uint256 amount);
    event CreditInsuree(address airline, address passenger, uint256 credit);
    event AirlineFunded(address funded, uint256 value);
    event Withdraw(address sender, uint256 amount);
    event InsurancePayout(address indexed airline, string flight);

    event FlightStatusInfo(
        address airline,
        string flight,
        uint256 timestamp,
        uint8 status
    );

    event OracleReport(
        address airline,
        string flight,
        uint256 timestamp,
        uint8 status
    );

    // Event fired when flight status request is submitted
    // Oracles track this and if they have a matching index
    // they fetch data and submit a response
    event OracleRequest(
        uint8 index,
        address airline,
        string flight,
        uint256 timestamp
    );
    event ProvideOracleResponse(
        uint8 indexes,
        address airlineAddr,
        string flight,
        uint256 timestamp,
        uint8 statusCode
    );

    function triggerOracleResponse(
        uint8 indexes,
        address airlineAddr,
        string memory flight,
        uint256 timestamp,
        uint8 statusCode
    ) external {
        emit ProvideOracleResponse(
            indexes,
            airlineAddr,
            flight,
            timestamp,
            statusCode
        );
    }

    function getResistration_fee()
        external
        view
        requireIsOperational
        returns (uint256)
    {
        return REGISTRATION_FEE;
    }

    // Register an oracle with the contract
    function registerOracle() external payable requireIsOperational {
        // Require registration fee
        require(msg.value >= REGISTRATION_FEE, "Registration fee is required");

        uint8[3] memory indexes = generateIndexes(msg.sender);

        oracles[msg.sender] = Oracle({isRegistered: true, indexes: indexes});
    }

    function isOracleRegistered(address oracleAddress)
        public
        view
        requireIsOperational
        returns (bool)
    {
        return oracles[oracleAddress].isRegistered;
    }

    function getMyIndexes()
        external
        view
        requireIsOperational
        returns (uint8[3] memory)
    {
        require(
            oracles[msg.sender].isRegistered,
            "Not registered as an oracle"
        );

        return oracles[msg.sender].indexes;
    }

    // Called by oracle when a response is available to an outstanding request
    // For the response to be accepted, there must be a pending request that is open
    // and matches one of the three Indexes randomly assigned to the oracle at the
    // time of registration (i.e. uninvited oracles are not welcome)
    function submitOracleResponse(
        uint8 index,
        address airline,
        string calldata flight,
        uint256 timestamp,
        uint8 statusCode
    ) external requireIsOperational {
        require(
            (oracles[msg.sender].indexes[0] == index) ||
                (oracles[msg.sender].indexes[1] == index) ||
                (oracles[msg.sender].indexes[2] == index),
            "Index does not match oracle request"
        );

        bytes32 key = keccak256(
            abi.encodePacked(index, airline, flight, timestamp)
        );
        require(
            oracleResponses[key].isOpen,
            "Flight or timestamp do not match oracle request"
        );

        oracleResponses[key].responses[statusCode].push(msg.sender);

        // Information isn't considered verified until at least MIN_RESPONSES
        // oracles respond with the *** same *** information
        emit OracleReport(airline, flight, timestamp, statusCode);
        if (
            oracleResponses[key].responses[statusCode].length >= MIN_RESPONSES
        ) {
            emit FlightStatusInfo(airline, flight, timestamp, statusCode);

            // Handle flight status as appropriate
            processFlightStatus(airline, flight, timestamp, statusCode);
        }
    }

    function getFlightKey(
        address airline,
        string calldata flight,
        uint256 timestamp
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(airline, flight, timestamp));
    }

    // Returns array of three non-duplicating integers from 0-9
    function generateIndexes(address account)
        internal
        returns (uint8[3] memory)
    {
        uint8[3] memory indexes;
        indexes[0] = getRandomIndex(account);

        indexes[1] = indexes[0];
        while (indexes[1] == indexes[0]) {
            indexes[1] = getRandomIndex(account);
        }

        indexes[2] = indexes[1];
        while ((indexes[2] == indexes[0]) || (indexes[2] == indexes[1])) {
            indexes[2] = getRandomIndex(account);
        }

        return indexes;
    }

    // Returns array of three non-duplicating integers from 0-9
    function getRandomIndex(address account) internal returns (uint8) {
        uint8 maxValue = 10;

        // Pseudo random number...the incrementing nonce adds variation
        uint8 random = uint8(
            uint256(
                keccak256(
                    abi.encodePacked(blockhash(block.number - nonce++), account)
                )
            ) % maxValue
        );

        if (nonce > 250) {
            nonce = 0; // Can only fetch blockhashes for last 256 blocks so we adapt
        }

        return random;
    }

    function isAirlineRegistered(address account) external view returns (bool) {
        require(account != address(0), "an invalid address account.");
        return flightSuretyData.isAirlineRegistered(account);
    }

    function isAirlineFunded(address account) external view returns (bool) {
        require(account != address(0), "an invalid address account.");
        return flightSuretyData.isAirlineFunded(account);
    }

    function airlineMembersLength() external view returns (uint256) {
        return flightSuretyData.airlineMembersLength();
    }

    function getAirlineVoteCount(address airlineAddr)
        external
        view
        returns (uint256)
    {
        require(airlineAddr != address(0), "an invalid address account.");
        return flightSuretyData.getAirlineVoteCount(airlineAddr);
    }

    /**
     * @dev Checks whether a flight is registered.
     *
     */
    function isFlightRegistered(
        address airline,
        string calldata flight,
        uint256 departureTime
    ) public view requireIsOperational returns (bool) {
        bytes32 key = getFlightKey(airline, flight, departureTime);
        return flights[key].isRegistered;
    }

    function pay()
    external
    payable
    {
        withdrawAllPassengerCredit();
    }
    // endregion
}

struct Insurance {
    uint256 claimable;
    address insuree;
}

interface FlightSuretyData {
    function registerAirline(
        string calldata name,
        address airlineAddr,
        bool _isOperational
    ) external;

    function isAirlineFunded(address account) external view returns (bool);

    function isAirlineRegistered(address account) external view returns (bool);

    function airlineMembersLength() external view returns (uint256);

    function getAirlineRegistrationStatus(address airlineAddr)
        external
        view
        returns (bool);

    function getAirlineOperationStatus(address airlineAddr)
        external
        view
        returns (bool);

    function getAirlineVoteCount(address airlineAddr)
        external
        view
        returns (uint256);

    function getCommiteeStatus(address commitee) external view returns (bool);

    function resetVoteCounter(address account) external;

    // oracle
    function getPassengerCreditBalance(address passenger) external view returns (uint256);

    function getPassengerBalance(address passengerAddr)
        external
        view
        returns (uint256);

    function getPremium(
        address airline,
        string calldata flight,
        uint256 departureTime,
        address passenger
    ) external view returns (uint256);

    function creditInsurees(
        address airline,
        string memory flight,
        uint256 timestamp,
        uint256 payOffNumerator,
        uint256 payOffDenominator
    ) external;

    function terminateInsurance(
        address airline,
        string memory flight,
        uint256 timestamp
    ) external;

    function addCommitees(address commitee) external;

    function voteAirlineRegistration(address airline) external;

    function fundAirline(address airline, uint256 amount) external;

    function purchaseInsurance(
        address airline,
        string calldata flight,
        uint256 timestamp,
        address passengerAddr,
        uint256 claimableAmount
    ) external;

    function withdrawPassengerCredit(address passengerAddr)
        external returns (uint256);
    /*


    function getAirlineFunding(address airline) external view returns (uint256);


*/
}
