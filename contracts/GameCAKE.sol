pragma solidity ^0.6.12;

import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/SafeBEP20.sol";
import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/IBEP20.sol";
import "@openzeppelin/contracts/math/Math.sol";

import "./interfaces/ICakeChef.sol";

contract GameCAKE {
    // import "@openzeppelin/contracts/math/SafeMath.sol";
    // import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
    // import "@openzeppelin/contracts/token/ERC20/IBEP20.sol";

    // using SafeERC20 for IBEP20;
    using SafeBEP20 for IBEP20;

    using Address for address;
    using SafeMath for uint256;
    using Math for uint256;
    // The CAKE TOKEN!
    IBEP20 public cake;
    address public cakeChef;

    //TODO add verification with this constant
    uint256 private constant ROLL_IN_PROGRESS = 42;

    // uint256 public pwin = 90; //probability of winning (100 = 100%)
    // uint256 public edge = 1.9; //edge percentage (100 = 100%)
    // uint256 public maxWin = 1; //max win (before edge is taken) as percentage of bankroll (100 = 100%)
    // uint256 public minBet = 1; // 0,1 BNB - https://eth-converter.com/
    // // uint256 constant minBet = 1 ether; // 1 BNB - https://eth-converter.com/
    // uint256 public maxInvestors = 10; //maximum number of investors
    // uint256 public houseEdge = 0.9; //edge percentage (100 = 100%)
    // uint256 public divestFee = 0.5; //divest fee percentage (100 = 100%)
    // uint256 public emergencyWithdrawalRatio = 0.1; //ratio percentage (100 = 100%)

    uint256 public pwin = 9000; //probability of winning (10000 = 100%)
    uint256 public edge = 190; //edge percentage (10000 = 100%)
    uint256 public maxWin = 100; //max win (before edge is taken) as percentage of bankroll (10000 = 100%)
    uint256 public minBet = 1; // 0,1 BNB - https://eth-converter.com/
    // uint256 constant minBet = 1 ether; // 1 BNB - https://eth-converter.com/
    uint256 public maxInvestors = 10; //maximum number of investors
    uint256 public houseEdge = 90; //edge percentage (10000 = 100%)
    uint256 public divestFee = 50; //divest fee percentage (10000 = 100%)
    uint256 public emergencyWithdrawalRatio = 10; //ratio percentage (100 = 100%)
    uint256 public startedBankroll = 10 ether; //10 Cake

    uint256 private safeGas = 25000;
    uint256 private constant INVALID_BET_MARKER = 99999;
    uint256 public constant EMERGENCY_TIMEOUT = 7 days;

    //TODO add getter & setter
    uint256 public minTimeToWithdraw = 1 hours; // 604800 = 1 week

    struct WithdrawalProposal {
        address payable toAddress;
        uint256 atTime;
    }

    uint256 public invested = 0; //currently invested
    uint256 public amountTotal = 0; //total invested
    uint256 public houseProfit = 0;

    address public owner;
    bool public paused;

    WithdrawalProposal public proposedWithdrawal;

    struct Investor {
        address investorAddress;
        // uint256 amountInvested;
        bool votedForEmergencyWithdrawal;
    }

    struct Bet {
        address playerAddress;
        uint256 amountBetted;
        uint256 numberRolled;
        uint256 winAmount;
        bool isWinned;
        bool isClaimed;
        uint256 timelock;
    }

    //Starting at 1
    mapping(uint256 => Investor) public investors;
    mapping(address => uint256) public investorIDs;
    uint256 public numInvestors = 0;

    mapping(uint256 => Bet) bets;
    mapping(address => uint256) public betsIDs;

    ///EVENTS
    event BetWon(
        address playerAddress,
        uint256 numberRolled,
        uint256 amountWon
    );
    event BetLost(address playerAddress, uint256 numberRolled);
    event EmergencyWithdrawalProposed();
    event EmergencyWithdrawalFailed(address withdrawalAddress);
    event EmergencyWithdrawalSucceeded(
        address withdrawalAddress,
        uint256 amountWithdrawn
    );
    event FailedSend(address receiver, uint256 amount);
    event ValueIsTooBig();

    event DiceRolled(uint256 indexed requestId, address indexed roller);
    event DiceLanded(uint256 indexed requestId, uint256 indexed result);

    /**
     * @dev Constructor
     * @notice TODO
     */
    constructor(address _cake, address _cakeChef) public {
        owner = msg.sender;
        cake = IBEP20(_cake);
        cakeChef = _cakeChef;
    }

    // Function to receive Ether. msg.data must be empty
    receive() external payable {
        _stakeCake();
    }

    // Fallback function is called when msg.data is not empty
    fallback() external payable {
        _stakeCake();
    }

    ///
    /// Main Functions
    ///

    function bet(uint256 _amount) public {
        require(!paused, "Contract is stopped"); // onlyIfNotStopped
        require(_amount > 0, "Only more than zero"); // onlyMoreThanZero
        require(_amount >= getMinInvestment(), "Only more than min investment"); // onlyMoreThanMinInvestment
        require(_amount >= minBet, "Only more than min bet"); // onlyMoreThanMinBet
        require(investorIDs[msg.sender] == 0, "Only for not investors"); // onlyNotInvestors

        uint256 allowance = cake.allowance(msg.sender, address(this));
        // uint256 allowance = cake.increaseAllowance(msg.sender, address(this));

        require(allowance >= _amount, "Check the token allowance");
        uint256 balance = cake.balanceOf(address(msg.sender));
        require(balance >= _amount, "not enought"); // onlyMoreThanZero

        //TODO how to divest smallest investors ?
        // if (numInvestors == maxInvestors) {
        //     uint256 smallestInvestorID = searchSmallestInvestor();
        //     divest(investors[smallestInvestorID].investorAddress);
        // }

        require(
            (((_amount * ((10000 - edge) - pwin)) / pwin) <=
                (maxWin * getTotalBalance()) / 10000),
            "You cannot enter in party"
        );

        numInvestors++;

        investorIDs[msg.sender] = numInvestors;

        investors[numInvestors].investorAddress = msg.sender;
        // investors[numInvestors].amountInvested = _amount;

        invested += _amount;
        amountTotal += _amount;

        //deposit

        bool success = cake.transferFrom(msg.sender, address(this), _amount);
        require(success, "Error during transfert"); // onlyMoreThanMinBet

        _stakeCake();

        uint256 _want = cake.balanceOf(address(this));

        if (_want > 0) {
            // _payFees(_want);
            _stakeCake();
        }

        //pick random number
        uint256 numberRolled = _rand();
        uint256 myid = _rand();
        // uint256 myid = _randBytes(numberRolled);

        //TODO create function to instanciate new Bet
        // bets[numInvestors] = Bet({
        bets[myid] = Bet({
            playerAddress: msg.sender,
            amountBetted: _amount,
            numberRolled: 0,
            winAmount: 0,
            isClaimed: false,
            isWinned: false,
            timelock: block.timestamp + minTimeToWithdraw
        });

        betsIDs[msg.sender] = myid;
        bets[myid].numberRolled = numberRolled;

        emit DiceRolled(numberRolled, msg.sender);

        //pick winner
        if (numberRolled - 1 < pwin) {
            //winning
            bets[myid].isWinned = true;

            uint256 winAmount = (bets[myid].amountBetted * (10000 - edge)) /
                pwin;

            // bets[myid].winAmount = bets[myid].amountBetted - winAmount;
            bets[myid].winAmount = winAmount - bets[myid].amountBetted;

            emit BetWon(
                bets[myid].playerAddress,
                bets[myid].numberRolled,
                bets[myid].winAmount
            );
        } else {
            //Loosing
            bets[myid].isClaimed = true;
            emit BetLost(bets[myid].playerAddress, bets[myid].numberRolled);
            //TODO do not sent but update data to allow user to claim
            //safeSend(thisBet.playerAddress, 1);

            houseProfit += ((bets[myid].amountBetted) * (houseEdge)) / 10000;
            //TODO remuburse initial Bankroll

            //safeSend(payable(owner), houseProfit);
        }

        // TODO
        // delete profitDistributed;
    }

    function claimBonus() public {
        require(investorIDs[msg.sender] != 0, "Only for investors"); // onlyInvestors

        uint256 betKey = betsIDs[msg.sender];

        require(bets[betKey].isWinned, "Not winned.");
        require(!bets[betKey].isClaimed, "Already claimed.");

        houseProfit -= bets[betKey].winAmount;

        _leaveStaking(bets[betKey].winAmount);

        uint256 _want = cake.balanceOf(address(this));
        if (_want > 0) {
            // _payFees(_want);
            _stakeCake();
        }
    }

    function claimBet() public {
        require(
            block.timestamp >= bets[betsIDs[msg.sender]].timelock,
            "Timelock: release time is before current time"
        );

        _divest(msg.sender);

        uint256 _want = cake.balanceOf(address(this));
        if (_want > 0) {
            // _payFees(_want);
            _stakeCake();
        }
    }

    function stakeCake() public {
        require(msg.sender == owner, "Only for owner"); //onlyOwner
        _stakeCake();
    }

    function getTotalBalance() public view returns (uint256) {
        // require(msg.sender == owner, "Only for owner"); //onlyOwner
        return
            getContractBalance()
                .add(balanceOfStakedWant()) //will not be correct if we sold syrup
                .add(balanceOfPendingWant());
    }

    function forceDivestOfAllInvestors() public payable {
        require(msg.sender == owner, "Only for owner"); //onlyOwner
        require(msg.value != 0, "reject value"); //rejectValue

        uint256 copyNumInvestors = numInvestors;
        for (uint256 i = 1; i <= copyNumInvestors; i++) {
            _divest(investors[i].investorAddress);
        }
    }

    function emergencyWithdrawal() public payable {
        require(msg.sender == owner, "Only for owner"); //onlyOwner
        require(msg.value != 0, "reject value"); //rejectValue

        // get money back to players
        forceDivestOfAllInvestors();

        //unstake other for Owner
        uint256 balanceOfStakedWant = balanceOfStakedWant();
        // unstacking
        CakeChef(cakeChef).leaveStaking(balanceOfStakedWant);
        // send
        uint256 _want = cake.balanceOf(address(this));
        cake.safeTransfer(msg.sender, _want);
    }

    ///
    /// PRIVATES FUNCTIONS
    ///
    function _stakeCake() internal {
        if (paused) return; //TODO add pausable requirement

        uint256 _want = cake.balanceOf(address(this));
        cake.safeApprove(cakeChef, 0);
        cake.safeApprove(cakeChef, _want);
        CakeChef(cakeChef).enterStaking(_want);
    }

    function _leaveStaking(uint256 _amount) internal {
        // unstacking
        CakeChef(cakeChef).leaveStaking(_amount);
        // send
        cake.safeTransfer(msg.sender, _amount);
    }

    function _divest(address currentInvestor) private {
        require(
            getBalanceFor(currentInvestor) >= 0,
            "only if investor balance is positive"
        ); //onlyIfInvestorBalanceIsPositive

        uint256 betKey = betsIDs[currentInvestor];
        uint256 currentID = investorIDs[currentInvestor];

        uint256 amountToReturn = getBalanceFor(currentInvestor);
        invested -= amountToReturn;
        uint256 divestFeeAmount = (amountToReturn * divestFee) / 10000;
        amountToReturn -= divestFeeAmount;

        _leaveStaking(amountToReturn);

        delete bets[betKey];
        delete betsIDs[msg.sender];

        delete investors[currentID];
        delete investorIDs[currentInvestor];
        //Reorder investors
        if (currentID != numInvestors) {
            // Get last investor
            Investor memory lastInvestor = investors[numInvestors];
            //Set last investor ID to investorID of divesting account
            investorIDs[lastInvestor.investorAddress] = currentID;
            //Copy investor at the new position in the mapping
            investors[currentID] = lastInvestor;
            //Delete old position in the mappping
            delete investors[numInvestors];
        }

        numInvestors--;
    }

    ///
    /// GETTERS FUNCTIONS
    ///

    function getLastBet()
        public
        view
        returns (
            address,
            uint256,
            uint256,
            uint256,
            bool,
            bool
        )
    {
        require(investorIDs[msg.sender] != 0, "Only for investors"); // onlyInvestors

        uint256 betKey = betsIDs[msg.sender];

        return (
            bets[betKey].playerAddress,
            bets[betKey].amountBetted,
            bets[betKey].numberRolled,
            bets[betKey].winAmount,
            bets[betKey].isClaimed,
            bets[betKey].isWinned
        );
    }

    function getHouseProfit() public view returns (uint256) {
        return houseProfit;
    }

    function getInvested() public view returns (uint256) {
        return invested;
    }

    function getBalanceFor(address currentInvestor)
        public
        view
        returns (uint256)
    {
        require(investorIDs[msg.sender] != 0, "Only for investors"); // onlyInvestors

        return bets[betsIDs[currentInvestor]].amountBetted;
        // return investors[investorIDs[currentInvestor]].amountInvested;
    }

    function getMinInvestment() public view returns (uint256) {
        if (numInvestors == maxInvestors) {
            uint256 investorID = searchSmallestInvestor();
            return getBalanceFor(investors[investorID].investorAddress);
        } else {
            return 0;
        }
    }

    ///
    /// HELPERS FUNCTIONS
    ///

    function balanceOfStakedWant() internal view returns (uint256) {
        // require(msg.sender == owner, "Only for owner");

        (uint256 _amount, ) = CakeChef(cakeChef).userInfo(
            uint256(0),
            address(this)
        );
        return _amount;
    }

    function balanceOfPendingWant() internal view returns (uint256) {
        return CakeChef(cakeChef).pendingCake(uint256(0), address(this));
    }

    function getContractBalance() internal view returns (uint256) {
        return cake.balanceOf(address(this));
    }

    function searchSmallestInvestor() internal view returns (uint256) {
        uint256 investorID = 1;
        for (uint256 i = 1; i <= numInvestors; i++) {
            if (
                getBalanceFor(investors[i].investorAddress) <
                getBalanceFor(investors[investorID].investorAddress)
            ) {
                investorID = i;
            }
        }

        return investorID;
    }

    ///
    /// DEBUG FUNCTIONS
    ///

    function numerator(uint256 amount) public view returns (uint256) {
        return ((amount * ((10000 - edge) - pwin)) / pwin);
    }

    function denominator() public view returns (uint256) {
        return ((maxWin * getTotalBalance()) / 10000);
    }

    ///
    /// RANDOM FUNCTIONS
    ///

    /**
     * @dev Generate array of random bytes
     * @return _ret bytes32 a random string
     * @notice Actually cause a out of Gas exception
     */
    function _randBytes() internal view returns (bytes32 _ret) {
        uint256 num = _rand();
        assembly {
            _ret := mload(0x10)
            mstore(_ret, 0x20)
            mstore(add(_ret, 0x20), num)
        }
    }

    /**
     * @dev Generate array of random bytes
     * @param _rand number to transform to bytes
     * @return _ret bytes32 the transformed string
     * @notice Actually cause a out of Gas exception
     */
    function _randBytes(uint256 _rand) internal pure returns (bytes32 _ret) {
        assembly {
            _ret := mload(0x10)
            mstore(_ret, 0x20)
            mstore(add(_ret, 0x20), _rand)
        }
    }

    /**
     * @dev Generate array of random bytes
     * @notice This function will generate a random numbre beetween 0 and 10000
     * @return uint256
     */
    function _rand() internal view returns (uint256) {
        return
            uint256(
                keccak256(abi.encodePacked(now, block.difficulty, msg.sender))
            ) % 10000;
    }
}

// function divest(address _address) public {
//     uint256 betKey = betsIDs[msg.sender];
//     require(
//         block.timestamp >= bets[betKey].timelock,
//         "Timelock: release time is before current time"
//     );

//     // _profitDistribution();
//     uint256 amountToReturn = getBalanceFor(msg.sender);
//     invested -= amountToReturn;
//     uint256 divestFeeAmount = (amountToReturn * divestFee) / 10000;
//     amountToReturn -= divestFeeAmount;

//     //TODO QUASI SAME PART AS
//     // unstacking
//     CakeChef(cakeChef).leaveStaking(amountToReturn);

//     // send
//     cake.safeTransfer(msg.sender, amountToReturn);

//     //TODO emit bet closed

//     //TODO Clean User Bet Data
//     delete bets[betKey];
//     delete betsIDs[msg.sender];

//     uint256 currentID = investorIDs[msg.sender];
//     delete investors[currentID];
//     delete investorIDs[msg.sender];
//     //Reorder investors
//     if (currentID != numInvestors) {
//         // Get last investor
//         Investor memory lastInvestor = investors[numInvestors];
//         //Set last investor ID to investorID of divesting account
//         investorIDs[lastInvestor.investorAddress] = currentID;
//         //Copy investor at the new position in the mapping
//         investors[currentID] = lastInvestor;
//         //Delete old position in the mappping
//         delete investors[numInvestors];
//     }

//     numInvestors--;
//     //TODO END QUASI SAME PART AS
// }
